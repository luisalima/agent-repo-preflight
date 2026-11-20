# One coding-agent CLI, installed at build time so the run itself needs no package registry.
FROM node:22-alpine
ARG PKG
RUN npm install -g --no-fund --no-audit "$PKG" && npm cache clean --force
USER node
WORKDIR /home/node/empty
