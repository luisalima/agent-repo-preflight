# Egress proxy for the agent containers: allows HTTPS (CONNECT) to the one host in $ALLOW_HOST, nothing else.
FROM alpine:3.20
RUN apk add --no-cache tinyproxy=1.11.2-r0
COPY proxy-entry.sh /proxy-entry.sh
USER tinyproxy
ENTRYPOINT ["/bin/sh", "/proxy-entry.sh"]
