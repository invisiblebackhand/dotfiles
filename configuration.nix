{ user, ... }:

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
