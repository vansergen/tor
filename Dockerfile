ARG ALPINE_VERSION=3.18.0

FROM alpine:${ALPINE_VERSION}

ARG TOR_VERSION=0.4.7.13-r2

RUN apk add --no-cache "tor>=${TOR_VERSION}"

COPY ./torrc.conf /etc/tor/torrc

VOLUME /var/lib/tor

EXPOSE 9050

ENTRYPOINT ["tor"]
