{pkgs, ...}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./fixture.py;
    })
  ];
  sops.secrets."fixture/paperlessPassword" = {};
  nixstead.services.productivity.paperless = {
    enable = true;
    port = 28982;
    paths = {
      dataDir = "/srv/paperless-data";
      mediaDir = "/srv/paperless-documents";
      consumeDir = "/srv/paperless-inbox";
    };
  };
  services.paperless = {
    passwordFile = "/run/secrets/fixture/paperlessPassword";
    settings = {
      PAPERLESS_ADMIN_USER = "admin";
      PAPERLESS_ADMIN_MAIL = "admin@example.test";
      PAPERLESS_OCR_LANGUAGE = "eng";
      PAPERLESS_TASK_WORKERS = 1;
      PAPERLESS_THREADS_PER_WORKER = 1;
      PAPERLESS_AI_ENABLED = false;
    };
  };
  virtualisation.memorySize = 4096;
}
