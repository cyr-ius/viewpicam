FROM alpine:3.20 AS builder

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
FROM python:3.12-alpine3.20 AS python-builder

WORKDIR /app

# Venv python
RUN python3 -m venv --system-site-packages --upgrade-deps /env
ENV VIRTUAL_ENV=/env
ENV PATH=$PATH:/env/bin

# Keeps Python from generating .pyc files in the container
ENV PYTHONDONTWRITEBYTECODE=1

# Turns off buffering for easier container logging
ENV PYTHONUNBUFFERED=1

# Add binaries and sources
ADD ./backend/requirements.txt requirements.txt

# Install dependencies
RUN apk add --no-cache --virtual build git build-base python3-dev cmake make gcc linux-headers ninja git rust cargo libressl-dev libffi-dev
RUN /env/bin/pip3 install --upgrade pip wheel
RUN /env/bin/pip3 install -v --no-cache-dir -r requirements.txt

# ------------- Builder angular ---------------
FROM --platform=$BUILDPLATFORM  node:current-alpine AS angular-builder

WORKDIR /dist/src/app

RUN npm install -g @angular/cli

COPY ./frontend/package.json ./frontend/package-lock.json ./
RUN npm ci

COPY frontend/ .

RUN npm run build --prod

# ------------- MAIN ---------------
FROM python:3.12-alpine3.20

COPY --from=builder /app/gpac-master/bin/gcc/MP4Box /usr/bin
COPY --from=builder /app/gpac-master/bin/gcc/gpac /usr/bin
COPY --from=builder /app/userland/build/bin /usr/bin
COPY --from=builder /app/userland/build/lib /usr/lib

COPY --from=python-builder /env /env
COPY ./backend/app /app/app
COPY ./backend/raspimjpeg /etc/raspimjpeg
COPY ./backend/alembic /app/alembic
COPY ./backend/alembic.ini /app/alembic.ini

# Install Frontend
RUN apk add --no-cache nginx supervisor
COPY site.conf /etc/nginx/http.d/default.conf
COPY --from=angular-builder /dist/src/app/dist/frontend/browser/ /usr/share/nginx/html
RUN ln -s /app/data /usr/share/nginx/html/data

WORKDIR /app

# set version label
LABEL org.opencontainers.image.source="https://github.com/cyr-ius/viewpicam"
LABEL org.opencontainers.image.description="Viewpicam - inspired by Rpi Cam Interface"
LABEL org.opencontainers.image.licenses="MIT"
LABEL maintaine="cyr-ius"

# Keeps Python from generating .pyc files in the container
ENV PYTHONDONTWRITEBYTECODE=1

# Turns off buffering for easier container logging
ENV PYTHONUNBUFFERED=1

# Enable VirtualEnv
ENV VIRTUAL_ENV="/env"
ENV PATH="/env/bin:$PATH"

VOLUME /app/macros
VOLUME /app/data
VOLUME /app/h264
VOLUME /app/config

ARG VERSION
ENV VERSION=${VERSION}

# Supervisord
COPY supervisord.conf /etc/supervisor/supervisord.conf
CMD ["/usr/bin/supervisord","-c","/etc/supervisor/supervisord.conf"]

EXPOSE 80/tcp
