[private]
default:
  @just --list --unsorted

# Start the dev server
dev:
  pnpm dev

# Build the site for deployment
build:
  pnpm build

# Start the preview server
preview:
  pnpm preview

# Remove untracked generated artifacts
clean:
  rm -rf "$PROJECT_ROOT/"{.astro,dist,node_modules,public/pagefind,result}

alias d := dev
alias b := build
alias p := preview
alias c := clean
