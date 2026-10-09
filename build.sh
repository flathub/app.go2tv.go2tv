flatpak-builder --force-clean --disable-cache --sandbox --user \
  --install-deps-from=flathub \
  --compose-url-policy=full \
  --mirror-screenshots-url=https://dl.flathub.org/media \
  --repo=repo --install builddir app.go2tv.go2tv.yml
