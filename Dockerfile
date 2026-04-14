ARG ALPINE_VERSION=3.23.3

FROM alpine:${ALPINE_VERSION}

ARG TOR_VERSION=0.4.9.6-r0
ARG LYREBIRD_VERSION=0.7.0-r5

RUN apk add --no-cache tor=${TOR_VERSION} && \
  apk add --no-cache lyrebird=${LYREBIRD_VERSION} && \
  mkdir /etc/tor/torrc.d

COPY ./torrc.conf /etc/tor/torrc

VOLUME /var/lib/tor /etc/tor

EXPOSE 9050

ENTRYPOINT ["tor"]
