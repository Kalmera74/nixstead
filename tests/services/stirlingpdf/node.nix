{...}: {
  nixstead.services.productivity.stirlingpdf = {
    enable = true;
    port = 28208;
  };
  services.stirling-pdf.environment = {
    SYSTEM_MAXFILESIZE = "1";
    STIRLING_TEMPFILES_DIRECTORY = "/var/lib/stirling-pdf/runtime-temp";
    SECURITY_ENABLELOGIN = "false";
  };
  systemd.services.stirling-pdf.preStart = ''
    mkdir -p /var/lib/stirling-pdf/runtime-temp
  '';
  systemd.services.stirling-pdf.environment.JAVA_TOOL_OPTIONS = "-Xms128m -Xmx768m";
  virtualisation.memorySize = 2048;
  virtualisation.diskSize = 4096;
}
