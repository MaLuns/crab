# Shared by test and packaging runs. Only products created for this run are disposable.
crab_prepare_temporary_products() {
  local temp_root
  temp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)" || return 1
  CRAB_PRODUCTS_STAGE="$(mktemp -d "$temp_root/crab-products.XXXXXXXX")" || return 1
  readonly CRAB_PRODUCTS_STAGE
  export CRAB_PRODUCTS_STAGE
  trap 'crab_clean_temporary_products' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

crab_clean_temporary_products() {
  local status=$? app message
  local lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  trap - EXIT
  trap '' HUP INT TERM
  # Xcode can register a signed product even when nobody opens it. Unregister it
  # while its bundle still exists, so a removed build cannot win a later lookup.
  for app in "$CRAB_PRODUCTS_STAGE/products/Crab.app" "$CRAB_PRODUCTS_STAGE/unpacked/Crab.app"; do
    if [[ -f "$app/Contents/Info.plist" ]] && ! message=$("$lsregister" -u "$app" 2>&1); then
      # A partial build or the ZIP verification copy may never have been
      # registered. kLSApplicationNotFoundErr already means it is absent.
      if [[ "$message" == *": -10814"* ]]; then continue; fi
      printf 'Could not unregister temporary bundle: %s\n%s\n' "$app" "$message" >&2
      if [[ $status == 0 ]]; then status=1; fi
    fi
  done
  if ! rm -rf "$CRAB_PRODUCTS_STAGE"; then
    echo "Could not remove temporary products: $CRAB_PRODUCTS_STAGE" >&2
    if [[ $status == 0 ]]; then status=1; fi
  fi
  exit "$status"
}
