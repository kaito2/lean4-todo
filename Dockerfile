# ── Build stage ────────────────────────────────────────────
FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y \
    curl git clang libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install elan (Lean version manager)
RUN curl https://elan.lean-lang.org/elan-init.sh -sSf | bash -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"

# Install Lean toolchain (cached layer)
WORKDIR /app
COPY lean-toolchain .
RUN elan toolchain install $(cat lean-toolchain)

# Symlink libpq into the Lean toolchain's sysroot so the bundled linker finds it
RUN ln -s /usr/lib/*/libpq.* "$(lean --print-prefix)/lib/"

# Copy project and build
COPY lakefile.lean lake-manifest.json ./
COPY Main.lean TodoApi.lean ./
COPY TodoApi/ TodoApi/
COPY ffi/ ffi/
RUN lake build

# ── Runtime stage ─────────────────────────────────────────
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/.lake/build/bin/todo_api /usr/local/bin/todo_api

EXPOSE 8080
CMD ["todo_api"]
