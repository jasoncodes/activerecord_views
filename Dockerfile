# syntax=docker/dockerfile:1.4

FROM ruby:3.1.4-slim-bookworm AS ruby

WORKDIR /app
SHELL ["/bin/bash", "-c"]
CMD ["/bin/bash"]

RUN \
  --mount=type=cache,id=activerecord_views-apt-cache,sharing=locked,target=/var/cache/apt \
  --mount=type=cache,id=activerecord_views-apt-lib,sharing=locked,target=/var/lib/apt \
  <<SH
  set -euo pipefail

  dpkg-reconfigure debconf --frontend=noninteractive
  rm /etc/apt/apt.conf.d/docker-clean
  cat > /etc/apt/apt.conf.d/docker-local <<EOF
  APT::Install-Suggests "0";
  APT::Install-Recommends "0";
  Binary::apt::APT::Keep-Downloaded-Packages "true";
EOF

  set -x

  apt-get update --yes

  apt-get install -y \
    build-essential gnupg2 postgresql-common libpq-dev

  /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh <<<$(echo)

  apt-get install -y postgresql-client-16
SH

COPY .tool-versions ./

RUN <<SH
  set -euo pipefail
  ruby --version
  (
    echo "ruby ${RUBY_VERSION?}"
  ) | diff - .tool-versions
SH

COPY Gemfile* *.gemspec Appraisals .
COPY lib/active_record_views/version.rb lib/active_record_views/
COPY gemfiles gemfiles

RUN \
  --mount=type=cache,id=activerecord_views-bundle-cache,target=/var/cache/bundle \
  <<SH
  set -euo pipefail
  BUNDLE_CACHE_PATH="/var/cache/bundle/debian-$(cat /etc/debian_version)-ruby-$RUBY_VERSION"

  (
    export GEM_HOME="$BUNDLE_CACHE_PATH"
    set -x

    gem install bundler
    bundle install
    bundle exec appraisal install
  )

  echo "Copying bundle cache to target..."
  tar c -C "$BUNDLE_CACHE_PATH" --anchored --no-wildcards-match-slash --exclude=./cache . | tar x -C "$GEM_HOME"
SH

COPY . ./

RUN <<SH
  set -euo pipefail
  for DIR in /tmp /app/tmp /app/spec/internal/db /app/spec/internal/app/models_temp /app/spec/internal/log; do
    mkdir -p "$DIR"
    chmod 1777 "$DIR"
  done
  useradd -m user
SH

USER user
