FROM alpine:3.18 AS builder

WORKDIR /app

RUN apk update && apk add --no-cache build-base git cmake bash make linux-headers
RUN git clone https://github.com/gpac/gpac.git gpac-master

WORKDIR /app/gpac-master

RUN ./configure --static-bin --use-zlib=no --prefix=/usr/bin
RUN make -j$(nproc)

WORKDIR /app

RUN git clone --branch 5.10.6 https://github.com/cyr-ius/userland.git userland

WORKDIR /app/userland
RUN sed -i 's/sudo//g' buildme
RUN /bin/bash -c ./buildme

# ------------- Builder python ---------------
FROM python:3.12-alpine AS python-builder

WORKDIR /app

# Venv python
RUN python3 -m venv --system-site-packages --upgrade-deps /env
ENV VIRTUAL_ENV=/env
ENV PATH=$PATH:/env/bin

# Keeps Python from generating .pyc files in the container
ENV PYTHONDONTWRITEBYTECODE=1

# Turns off buffering for easier container logging
ENV PYTHONUNBUFFERED=1

# Install dependencies
RUN apk add --no-cache --virtual build git build-base python3-dev cmake make gcc linux-headers ninja git rust cargo libressl-dev libffi-dev
RUN /env/bin/pip3 install --upgrade pip wheel

RUN git clone https://github.com/cyr-ius/viewpicam-backend backend

WORKDIR /app/backend

RUN /env/bin/pip3 install -v --no-cache-dir -r requirements.txt

# ------------- Builder angular ---------------
FROM --platform=$BUILDPLATFORM  node:current-alpine AS angular-builder

WORKDIR /dist/src/app

RUN apk add --no-cache git

RUN npm install -g @angular/cli

RUN export FRONTEND_VERSION=$(curl --silent "https://api.github.com/repos/cyr-ius/viewpicam-frontend/releases/latest"  | grep -Po "(?<=\"tag_name\": \").*(?=\")");echo "export FRONTEND_VERSION=${FRONTEND_VERSION}" > /envfile

RUN . /envfile;git clone https://github.com/cyr-ius/viewpicam-frontend frontend

WORKDIR /dist/src/app/frontend
RUN npm ci
RUN npm run build --prod
RUN ls

# ------------- MAIN ---------------
FROM nginx:alpine3.20-slim

COPY --from=builder /app/gpac-master/bin/gcc/MP4Box /usr/bin
COPY --from=builder /app/gpac-master/bin/gcc/gpac /usr/bin
COPY --from=builder /app/userland/build/bin /usr/bin
COPY --from=builder /app/userland/build/lib /usr/lib

COPY --from=angular-builder /dist/src/app/frontend/dist/frontend/browser /usr/share/nginx/html

COPY --from=python-builder /env /env
COPY --from=python-builder /app/backend/app /app/app
COPY --from=python-builder /app/backend/raspimjpeg /etc/raspimjpeg
COPY --from=python-builder /app/backend/alembic /app/alembic
COPY --from=python-builder /app/backend/alembic.ini /app/alembic.ini

WORKDIR /app

# set version label
LABEL org.opencontainers.image.source="https://github.com/cyr-ius/viewpicam"
LABEL org.opencontainers.image.description="Viewpicam - inspired by Rpi Cam Interface"
LABEL org.opencontainers.image.licenses="MIT"
LABEL maintaine="cyr-ius"

RUN apk add --no-cache python3 && ln -sf /usr/bin/python3 /usr/local/bin/python3

COPY site.conf /etc/nginx/conf.d/default.conf

COPY run-fastapi.sh /docker-entrypoint.d/05-run-fastapi.sh
RUN chmod +x /docker-entrypoint.d/05-run-fastapi.sh

VOLUME /app/macros
VOLUME /app/data
VOLUME /app/h264
VOLUME /app/config

ARG VERSION
ENV VERSION=${VERSION}
ENV VIRTUAL_ENV=/env
ENV PATH=/env/bin:$PATH

EXPOSE 80/tcp
