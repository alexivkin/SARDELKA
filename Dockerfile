FROM alpine

MAINTAINER Alex Ivkin <alex@ivkin.net>

COPY backup /sardelka/
COPY backup-* /sardelka/
COPY restore-* /sardelka/

ARG UID=1000
ARG GID=1000

RUN apk add --no-cache bash gawk sed grep bc coreutils rsync openssh && \
    umask 0002 && \
	deluser $(getent passwd 33 | cut -d: -f1) && \
    delgroup $(getent group 33 | cut -d: -f1) 2>/dev/null || true && \
	addgroup -g $GID sardelka && \
	adduser -Ss /bin/false -u $UID -G sardelka -h /home/sardelka sardelka && \
    chown sardelka:sardelka /sardelka/ /sardelka/* /home/sardelka && \
    chmod 755 /sardelka/backup /sardelka/backup-* /sardelka/restore-*

VOLUME ["/backups"]
USER sardelka
WORKDIR /sardelka/

CMD [ "/sardelka/backup" ]
