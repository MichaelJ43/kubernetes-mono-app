"""Deploy orchestrator: API Gateway routes + async worker via self-invoke."""
from __future__ import annotations

import base64
import io
import json
import os
import shutil
import tarfile
import time
import uuid
from typing import Any, Dict

import boto3
import yaml
from botocore.signers import RequestSigner
from kubernetes import client, utils

REGION = os.environ.get("AWS_REGION_NAME") or os.environ.get("AWS_REGION", "us-east-1")
SITE_MODE_PARAM = os.environ["SITE_MODE_PARAM"]
SOURCE_BUCKET = os.environ["SOURCE_BUCKET"]
PARKED_BUCKET = os.environ["PARKED_BUCKET"]
PARKED_CF_ID = os.environ["PARKED_CF_ID"]
JOB_TABLE = os.environ["JOB_TABLE"]
CLUSTER_NAME = os.environ["CLUSTER_NAME"]
EKS_ENDPOINT = os.environ["EKS_ENDPOINT"]
EKS_CA_B64 = os.environ["EKS_CA_B64"]

ddb = boto3.client("dynamodb", region_name=REGION)
ssm = boto3.client("ssm", region_name=REGION)
s3 = boto3.client("s3", region_name=REGION)
lmd = boto3.client("lambda", region_name=REGION)
cf = boto3.client("cloudfront", region_name=REGION)


def _resp(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def get_site_mode() -> str:
    try:
        r = ssm.get_parameter(Name=SITE_MODE_PARAM)
        v = (r["Parameter"]["Value"] or "").strip().lower()
    except ssm.exceptions.ParameterNotFound:
        v = ""
    if v == "static":
        return "static"
    return "cluster"


def put_site_mode(mode: str) -> None:
    ssm.put_parameter(Name=SITE_MODE_PARAM, Value=mode, Type="String", Overwrite=True)


def norm_target(s: str) -> str:
    s = (s or "").lower().strip()
    if s in ("kubernetes", "k8s", "cluster"):
        return "cluster"
    if s in ("static", "parked"):
        return "static"
    raise ValueError("target must be kubernetes or static")


def create_job(status: str = "queued") -> str:
    jid = str(uuid.uuid4())
    now = int(time.time())
    ddb.put_item(
        TableName=JOB_TABLE,
        Item={
            "job_id": {"S": jid},
            "status": {"S": status},
            "detail": {"S": ""},
            "expires_at": {"N": str(now + 7 * 24 * 3600)},
        },
    )
    return jid


def update_job(jid: str, status: str, detail: str = "") -> None:
    ddb.update_item(
        TableName=JOB_TABLE,
        Key={"job_id": {"S": jid}},
        UpdateExpression="SET #s = :s, #d = :d",
        ExpressionAttributeNames={"#s": "status", "#d": "detail"},
        ExpressionAttributeValues={":s": {"S": status}, ":d": {"S": detail[:35000]}},
    )


def invoke_async_worker(job_id: str, action: str, payload: Dict[str, Any]) -> None:
    fn_name = os.environ["AWS_LAMBDA_FUNCTION_NAME"]
    lmd.invoke(
        FunctionName=fn_name,
        InvocationType="Event",
        Payload=json.dumps(
            {"internal": True, "job_id": job_id, "action": action, "payload": payload}
        ).encode(),
    )


def get_bearer_token(cluster_name: str, region: str) -> str:
    session = boto3.session.Session()
    sts_client = session.client("sts", region_name=region)
    service_id = sts_client.meta.service_model.service_id
    signer = RequestSigner(
        service_id,
        region,
        "sts",
        "aws4_request",
        session.get_credentials(),
        session.events,
    )
    url = f"https://sts.{region}.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15"
    signed_url = signer.generate_presigned_url(
        {
            "method": "GET",
            "url": url,
            "body": {},
            "headers": {"x-k8s-aws-id": cluster_name},
            "context": {},
        },
        region_name=region,
        expires_in=60,
        operation_name="",
    )
    tok = "k8s-aws-v1." + base64.urlsafe_b64encode(signed_url.encode("utf-8")).decode("utf-8").rstrip("=")
    return tok


def k8s_api_client() -> client.ApiClient:
    token = get_bearer_token(CLUSTER_NAME, REGION)
    ca_bytes = base64.b64decode(EKS_CA_B64)
    cfg = client.Configuration()
    cfg.host = EKS_ENDPOINT
    with open("/tmp/eks-ca.crt", "wb") as f:
        f.write(ca_bytes)
    cfg.ssl_ca_cert = "/tmp/eks-ca.crt"
    cfg.api_key = {"authorization": "Bearer " + token}
    return client.ApiClient(cfg)


def apply_k8s_bundle(extract_dir: str) -> None:
    kclient = k8s_api_client()
    k8s_dir = os.path.join(extract_dir, "k8s")
    if not os.path.isdir(k8s_dir):
        raise RuntimeError("bundle missing k8s/ directory")
    paths: list[str] = []
    for root, _dirs, names in os.walk(k8s_dir):
        for n in sorted(names):
            if n.endswith((".yaml", ".yml")):
                paths.append(os.path.join(root, n))
    paths.sort(key=lambda p: (0 if "namespace" in os.path.basename(p).lower() else 1, p))
    for fp in paths:
        with open(fp, encoding="utf-8") as fh:
            docs = list(yaml.safe_load_all(fh))
        for doc in docs:
            if doc is None:
                continue
            try:
                utils.create_from_dict(kclient, doc, verbose=False)
            except Exception as e:  # noqa: BLE001
                err = str(e).lower()
                if "already exists" in err or "conflict" in err:
                    continue
                raise


def _content_type(path: str) -> str:
    if path.endswith(".html"):
        return "text/html; charset=utf-8"
    if path.endswith(".json"):
        return "application/json"
    return "application/octet-stream"


def sync_static_to_parked(static_root: str) -> None:
    paginator = s3.get_paginator("list_objects_v2")
    keys: list[str] = []
    for page in paginator.paginate(Bucket=PARKED_BUCKET):
        for obj in page.get("Contents", []):
            keys.append(obj["Key"])
    if keys:
        for i in range(0, len(keys), 900):
            batch = [{"Key": k} for k in keys[i : i + 900]]
            s3.delete_objects(Bucket=PARKED_BUCKET, Delete={"Objects": batch})
    for dirpath, _dirs, filenames in os.walk(static_root):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, static_root).replace("\\", "/")
            s3.upload_file(
                full,
                PARKED_BUCKET,
                rel,
                ExtraArgs={
                    "ContentType": _content_type(fn),
                    "CacheControl": "max-age=60",
                },
            )
    cf.create_invalidation(
        DistributionId=PARKED_CF_ID,
        InvalidationBatch={
            "Paths": {"Quantity": 1, "Items": ["/*"]},
            "CallerReference": str(time.time()),
        },
    )


def clear_parked_bucket() -> None:
    paginator = s3.get_paginator("list_objects_v2")
    keys: list[str] = []
    for page in paginator.paginate(Bucket=PARKED_BUCKET):
        for obj in page.get("Contents", []):
            keys.append(obj["Key"])
    if keys:
        for i in range(0, len(keys), 900):
            batch = [{"Key": k} for k in keys[i : i + 900]]
            s3.delete_objects(Bucket=PARKED_BUCKET, Delete={"Objects": batch})
    cf.create_invalidation(
        DistributionId=PARKED_CF_ID,
        InvalidationBatch={
            "Paths": {"Quantity": 1, "Items": ["/*"]},
            "CallerReference": str(time.time()),
        },
    )


def download_extract(bundle_key: str, dest: str) -> None:
    bio = io.BytesIO()
    s3.download_fileobj(SOURCE_BUCKET, bundle_key, bio)
    bio.seek(0)
    with tarfile.open(fileobj=bio, mode="r:gz") as tf:
        tf.extractall(dest)


def run_deploy(job_id: str, payload: Dict[str, Any]) -> None:
    bundle_key = payload.get("bundle_key")
    if not bundle_key:
        raise ValueError("bundle_key required")
    mode = get_site_mode()
    extract = f"/tmp/bundle-{job_id}"
    os.makedirs(extract, exist_ok=True)
    try:
        download_extract(bundle_key, extract)
        if mode == "cluster":
            apply_k8s_bundle(extract)
        else:
            static_root = os.path.join(extract, "static")
            if not os.path.isdir(static_root):
                raise RuntimeError("bundle missing static/ directory")
            sync_static_to_parked(static_root)
        update_job(job_id, "succeeded", f"deploy {mode} {bundle_key}")
    except Exception as e:  # noqa: BLE001
        update_job(job_id, "failed", str(e))
        raise
    finally:
        shutil.rmtree(extract, ignore_errors=True)


def run_swap(job_id: str, payload: Dict[str, Any]) -> None:
    current = get_site_mode()
    force = bool(payload.get("force_toggle", payload.get("forceToggle", False)))
    target_raw = payload.get("target") or payload.get("desired")
    only_if = bool(payload.get("only_if_inactive", payload.get("onlyIfInactive", False)))

    if force and not target_raw:
        new_mode = "static" if current == "cluster" else "cluster"
        put_site_mode(new_mode)
        update_job(job_id, "succeeded", f"force toggled site_mode to {new_mode}")
        return

    if not target_raw:
        raise ValueError("target required unless force_toggle without target")

    target = norm_target(str(target_raw))
    if only_if and not force and current == target:
        update_job(job_id, "succeeded", "no-op: already on target")
        return
    put_site_mode(target)
    update_job(job_id, "succeeded", f"site_mode={target}")


def run_teardown(job_id: str, payload: Dict[str, Any]) -> None:
    scope = (payload.get("scope") or "active").lower()
    both = scope == "both"
    active = get_site_mode()
    msgs: list[str] = []
    try:
        if both:
            clear_parked_bucket()
            msgs.append("cleared parked site bucket (both)")
            msgs.append("EKS stack not destroyed here; use full-undeploy or terraform destroy")
        elif active == "static":
            clear_parked_bucket()
            msgs.append("cleared parked site (active static)")
        else:
            msgs.append("cluster active: workload/infra teardown not automated in Lambda")
        update_job(job_id, "succeeded", "; ".join(msgs))
    except Exception as e:  # noqa: BLE001
        update_job(job_id, "failed", str(e))
        raise


def route_api(event: Dict[str, Any]) -> Dict[str, Any]:
    rc = event.get("requestContext", {})
    http = rc.get("http", {}) if isinstance(rc, dict) else {}
    method = (http.get("method") or "GET").upper()
    raw_path = event.get("rawPath") or ""
    if method != "POST":
        return _resp(405, {"error": "method not allowed"})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        body = {}

    if raw_path.endswith("/deploy"):
        jid = create_job("queued")
        invoke_async_worker(jid, "deploy", body)
        return _resp(202, {"job_id": jid})
    if raw_path.endswith("/swap"):
        jid = create_job("queued")
        invoke_async_worker(jid, "swap", body)
        return _resp(202, {"job_id": jid})
    if raw_path.endswith("/teardown"):
        jid = create_job("queued")
        invoke_async_worker(jid, "teardown", body)
        return _resp(202, {"job_id": jid})
    return _resp(404, {"error": "not found", "path": raw_path})


def process_internal(event: Dict[str, Any]) -> Dict[str, Any]:
    job_id = event["job_id"]
    action = event["action"]
    payload = event.get("payload") or {}
    update_job(job_id, "running", action)
    try:
        if action == "deploy":
            run_deploy(job_id, payload)
        elif action == "swap":
            run_swap(job_id, payload)
        elif action == "teardown":
            run_teardown(job_id, payload)
        else:
            update_job(job_id, "failed", f"unknown action {action}")
    except Exception as e:  # noqa: BLE001
        update_job(job_id, "failed", str(e))
    return {"ok": True}


def handler(event, context):
    if isinstance(event, dict) and event.get("internal"):
        return process_internal(event)
    if isinstance(event, dict) and "requestContext" in event:
        return route_api(event)
    if isinstance(event, dict) and "action" in event and "job_id" in event:
        return process_internal({"internal": True, **event})
    return _resp(400, {"error": "unrecognized event"})
