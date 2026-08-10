# Linux LOVE under a virtual display with software GL, for the controlled
# visual runner (roadmap T0.2).
#
#   docker build -t voxel-characters-runner:local mods/voxel_characters/tools/runner
#
# NOT BUILT OR MEASURED YET. This file is the recipe, reviewable and runnable,
# and `runner.sh probe docker` reports the image as missing with this exact
# command as the next action. What it cannot tell you is whether the OUTPUT is
# comparable to the macOS native output, and the answer is almost certainly no:
# see LIMITATIONS in README.md. Read that before trusting a number from here.
FROM debian:bookworm-slim

# love          Debian bookworm ships 11.4, the host runs 11.5. A different
#               LOVE build is itself a delta source, before GL is considered.
# xvfb          a virtual display, because LOVE needs a window to get a GL
#               context. There is no headless path (tools/render/README.md).
# mesa dri      software rasteriser. llvmpipe, not the Apple GL the thresholds
#               in this repo were measured against.
# ffmpeg        clip.sh and trailer.sh assemble with it.
# luajit        so the offline suite and the Lua gates can run in here too.
RUN apt-get update && apt-get install -y --no-install-recommends \
      love \
      xvfb \
      libgl1-mesa-dri \
      libglu1-mesa \
      mesa-utils \
      ffmpeg \
      luajit \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Force the software path rather than hoping for it. Without this, a host that
# does pass a GPU through would give a third rendering behaviour, and then
# "the docker backend" would not name one procedure.
ENV LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    MESA_GL_VERSION_OVERRIDE=3.3 \
    SDL_AUDIODRIVER=dummy

# The repo is bind-mounted rather than copied, on purpose: `data/generated/`
# and `assets/generated/` are gitignored because they are derived from the
# player's own ROM, so an image built from this repository has no sprites and
# no constants to render. The mount is the only way the container sees them,
# and it is also why nothing here needs a ROM of its own.
WORKDIR /repo

# -a picks a free display number, so two containers do not fight over :99.
# The screen is 1280x800x24 to match tools/render/conf.lua; a smaller virtual
# screen than the window would clip the harness.
ENTRYPOINT ["xvfb-run", "-a", "-s", "-screen 0 1280x800x24"]
CMD ["/bin/sh", "-c", "glxinfo -B | head -5 && love --version"]
