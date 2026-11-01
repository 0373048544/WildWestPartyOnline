FROM ubuntu:24.04

ARG GODOT_RELEASE=4.7.2-stable

ENV DEBIAN_FRONTEND=noninteractive \
    WWPO_BIND=0.0.0.0 \
    PORT=7000

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    unzip \
    libfontconfig1 \
    libx11-6 \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libxi6 \
    libgl1 \
    libasound2t64 \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q \
    "https://github.com/godotengine/godot-builds/releases/download/${GODOT_RELEASE}/Godot_v${GODOT_RELEASE}_linux.x86_64.zip" \
    -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp/godot \
    && mv "/tmp/godot/Godot_v${GODOT_RELEASE}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot /tmp/godot.zip

WORKDIR /app
COPY . /app

# Pre-import project resources at image-build time so the free runtime instance
# does less work on its first boot. If Godot returns non-zero only because no
# display is present, --headless avoids that requirement.
RUN godot --headless --editor --path /app --quit

EXPOSE 7000

CMD ["sh", "-c", "exec godot --headless --path /app server/DedicatedServer.tscn -- --port=${PORT:-7000}"]
