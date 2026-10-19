FROM alpine:3.24.2

ARG TOR_VERSION=0.4.9.14-r0
ARG LYREBIRD_VERSION=0.8.1-r7

RUN apk add --no-cache tor=${TOR_VERSION} lyrebird=${LYREBIRD_VERSION} && \
  mkdir /etc/tor/torrc.d

COPY ./torrc.conf /etc/tor/torrc

VOLUME /var/lib/tor /etc/tor

EXPOSE 9050

ENTRYPOINT ["tor"]
