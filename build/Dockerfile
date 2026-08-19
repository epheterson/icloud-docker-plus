# Overlay build: the verified working tree currently running on the NAS.
#
# The plus image is assembled by merging feature branches that are still
# open upstream, and four of the six currently conflict against main. That
# integration is worth doing carefully, not under time pressure -- so this
# layers the exact files verified live onto the last good published image,
# giving a reboot-safe artifact with zero merge risk.
#
# Replace with a real source build once the branch integration lands.
FROM ghcr.io/epheterson/icloud-docker-plus:0.9.2

COPY src/__init__.py src/web.py src/web_signals.py src/sync.py \
     src/notify.py src/config_parser.py /app/src/
COPY src/templates/ /app/src/templates/
COPY tools/ /app/tools/
