{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    imagemagick
    swayimg
    yewtube
    yt-dlp
    ffmpeg_7
    handbrake
  ];
}
