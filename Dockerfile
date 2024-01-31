ARG ALPINE_VERSION=3.19.1

FROM alpine:${ALPINE_VERSION}

ARG TOR_VERSION=0.4.8.10-r0

RUN apk add --no-cache "tor>=${TOR_VERSION}"

COPY ./torrc.conf /etc/tor/torrc

VOLUME /var/lib/tor

EXPOSE 9050

ENTRYPOINT ["tor"]
