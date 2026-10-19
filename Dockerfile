FROM alpine:3.24.2

RUN apk add --no-cache tor lyrebird && \
  mkdir /etc/tor/torrc.d && \
  chmod 700 /var/lib/tor

COPY ./torrc.conf /etc/tor/torrc

USER tor

VOLUME /var/lib/tor

EXPOSE 9050

ENTRYPOINT ["tor"]
