ARG ALPINE_VERSION=3.22.0

FROM alpine:${ALPINE_VERSION}

ARG TOR_VERSION=0.4.8.16-r0
ARG LYREBIRD_VERSION=0.6.0-r1
ARG LYREBIRD_REPOSITORY=https://dl-cdn.alpinelinux.org/alpine/edge/community

RUN apk add --no-cache tor=${TOR_VERSION} && \
  apk add --no-cache lyrebird=${LYREBIRD_VERSION} --repository ${LYREBIRD_REPOSITORY} && \
  mkdir /etc/tor/torrc.d

COPY ./torrc.conf /etc/tor/torrc

VOLUME /var/lib/tor /etc/tor

EXPOSE 9050

ENTRYPOINT ["tor"]
