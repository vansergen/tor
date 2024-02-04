ARG ALPINE_VERSION=3.19.1

FROM alpine:${ALPINE_VERSION}

ARG TOR_VERSION=0.4.8.10

RUN apk add --no-cache "tor>=${TOR_VERSION}" && \
  mkdir /etc/tor/torrc.d

COPY ./torrc.conf /etc/tor/torrc

VOLUME /var/lib/tor

EXPOSE 9050

ENTRYPOINT ["tor"]
