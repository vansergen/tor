ARG ALPINE_VERSION=3.21.0

FROM alpine:${ALPINE_VERSION}

ARG TOR_VERSION=0.4.8.12-r0
ARG LYREBIRD_VERSION=0.2.0-r2
ARG LYREBIRD_REPOSITORY=http://dl-cdn.alpinelinux.org/alpine/edge/testing

RUN apk add --no-cache tor=${TOR_VERSION} && \
  apk add --no-cache lyrebird=${LYREBIRD_VERSION} --repository ${LYREBIRD_REPOSITORY} && \
  mkdir /etc/tor/torrc.d

COPY ./torrc.conf /etc/tor/torrc

VOLUME /var/lib/tor

EXPOSE 9050

ENTRYPOINT ["tor"]
