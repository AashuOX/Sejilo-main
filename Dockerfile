FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

CMD ["/bin/bash"]
