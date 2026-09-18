{ config, user, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;

  # Self-heal for zsh sessions that inherit nix-darwin's "environment already
  # set" flag without the PATH that belongs to it. Seen 2026-09-18: Terminal.app
  # was relaunched by an AppleScript from an agent shell, inherited
  # __NIX_DARWIN_SET_ENVIRONMENT_DONE=1, and every new window was born with
  # PATH=/usr/bin:/bin because /etc/zshenv trusted the flag and skipped
  # set-environment. nix-darwin emits shellInit into /etc/zshenv inside its
  # `[[ -o rcs ]]` block, directly after that gate and before ~/.zshenv,
  # /etc/zshrc (Homebrew) and ~/.zshrc (the PATH prepends), so the repair runs
  # before anything builds on PATH. The condition tests the PATH, not the flag,
  # so a renamed flag cannot silence it. Every repair appends one line to
  # ~/.local/state/nix-darwin-path-guard.log and, in interactive shells, prints
  # one stderr warning, so a recurring launcher stays visible instead of being
  # papered over. The line also records the first 512 characters of the
  # pre-repair PATH and discards the remainder: once the guard has run, that
  # field is the only surviving evidence of what the parent handed over, and
  # the evidence-bearing entries (a probe marker, the three ~/.zshrc prepends)
  # are at the start of the string. Log bound: before appending, if the file
  # exceeds 64 KiB only its last 100 lines are kept, so its worst case of 100
  # 592-byte records stays under 64 KiB. zsh builtins only; no fork unless the
  # state directory is missing. Regression test: tests/path-guard.test.sh.
  programs.zsh.shellInit = ''
    if [[ ":$PATH:" != *":/run/current-system/sw/bin:"* ]]; then
      __nix_darwin_path_guard() {
        local log="''${XDG_STATE_HOME:-$HOME/.local/state}/nix-darwin-path-guard.log"
        local -a size lines
        local fmt='%D{%Y-%m-%d %H:%M:%S}' stamp mode=n found="''${PATH-}"
        stamp="''${(%)fmt}"
        unset __NIX_DARWIN_SET_ENVIRONMENT_DONE __HM_SESS_VARS_SOURCED
        . ${config.system.build.setEnvironment}
        [[ -d "''${log:h}" ]] || mkdir -p "''${log:h}" 2>/dev/null
        if zmodload -F zsh/stat b:zstat 2>/dev/null \
          && zstat -A size +size -- "$log" 2>/dev/null && (( size[1] > 65536 )); then
          lines=("''${(@f)$(<"$log")}")
          (( $#lines > 100 )) && print -rl -- "''${(@)lines[-100,-1]}" > "$log" 2>/dev/null
        fi
        [[ -o interactive ]] && mode=y
        print -r -- "$stamp pid=$$ ppid=$PPID term=''${TERM_PROGRAM:-?} interactive=$mode path=''${found[1,512]}" >> "$log" 2>/dev/null
        if [[ -o interactive ]]; then
          print -u2 "nix-darwin: PATH lacked /run/current-system/sw/bin; environment re-applied (log: $log)"
        fi
        return 0
      }
      __nix_darwin_path_guard
      unfunction __nix_darwin_path_guard
    fi
  '';

  # No `system.defaults` block, and no networking.hostName / computerName /
  # localHostName. Deliberate: this machine runs licensed trading software
  # (MotiveWave, Bookmap, Parallels + R-Trader Pro) and the first switch must
  # change no OS-level setting. Add macOS defaults later, one at a time.

  nix-homebrew = {
    enable = true;
    inherit user;
    # Homebrew was NOT installed on this machine at baseline (2026-09-16), so this
    # is a first install, not a migration; autoMigrate has nothing to migrate.
    # Kept so the config remains correct if ever applied to a machine that has one.
    autoMigrate = true;
    # enableRosetta is not set: nix-homebrew defaults it to false, and true would
    # create a second Intel Homebrew under /usr/local.
    # mutableTaps is not set: left at its default (true) for the first switch.
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "none";    # never remove anything not listed here
    onActivation.upgrade = false;     # never upgrade packages during activation
    onActivation.autoUpdate = false;  # never update Homebrew itself during activation
    brews = [
      "herdr"  # terminal multiplexer / agent runner
      "gh"     # GitHub CLI
      # Deliberately NOT here:
      #   node -- Node 24.19.0 is already installed from the official pkg at
      #           /usr/local; a brew node would be a second, competing install.
      #   jq   -- provided by nix in home.nix home.packages (macOS also ships
      #           /usr/bin/jq); a brew jq would be a third copy.
      #   claude-code -- keeping the native installer at ~/.local/bin/claude.
      #   tmux -- fails against the Homebrew pinned by flake.lock (6.0.1) with
      #           "unknown install step: run". See decisions.md 6.8.
    ];
    casks = [
      "codex"  # OpenAI Codex CLI -- a cask, not a formula (logged in later)
    ];
  };
}
