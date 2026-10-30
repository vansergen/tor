FROM alpine:3.24.3

RUN apk add --no-cache tor lyrebird && \
  mkdir /etc/tor/torrc.d && \
  chmod 700 /var/lib/tor

COPY ./torrc.conf /etc/tor/torrc
COPY ./bin/tor-migrate /usr/local/bin/tor-migrate

USER tor

VOLUME /var/lib/tor

EXPOSE 9050

ENTRYPOINT ["tor"]
