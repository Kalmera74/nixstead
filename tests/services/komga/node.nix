{...}: {
  nixstead.services.media.komga = {
    enable = true;
    port = 28204;
  };

  systemd.services.komga.environment.JAVA_TOOL_OPTIONS = "-Xms128m -Xmx512m";

  virtualisation.memorySize = 1536;
  virtualisation.diskSize = 4096;
}
