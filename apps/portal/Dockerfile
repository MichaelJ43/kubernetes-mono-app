FROM golang:1.23-alpine AS build
ENV GOTOOLCHAIN=auto
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /portal ./cmd/portal

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /
COPY --from=build /portal /portal
USER nonroot:nonroot
EXPOSE 8080
ENV HTTP_ADDR=":8080"
ENTRYPOINT ["/portal"]
