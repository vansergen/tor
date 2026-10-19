FROM alpine:3.24.2

ARG TOR_VERSION=0.4.9.14-r0
ARG LYREBIRD_VERSION=0.8.1-r7

RUN apk add --no-cache tor=${TOR_VERSION} lyrebird=${LYREBIRD_VERSION} && \
  mkdir /etc/tor/torrc.d && \
  chmod 700 /var/lib/tor

COPY ./torrc.conf /etc/tor/torrc

USER tor

VOLUME /var/lib/tor

EXPOSE 9050

ENTRYPOINT ["tor"]
