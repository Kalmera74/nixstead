{host}: {
  title = host.hostName;
  background = "#0b0d10";
  theme = "dark";
  color = "neutral";
  headerStyle = "underlined";
  quicklaunch = {
    searchDescriptions = true;
    hideInternetSearch = true;
    hideVisitURL = true;
  };

  layout = [
    {
      "Arr" = {
        style = "row";
        columns = 5;
      };
    }
    {
      "Media" = {
        style = "row";
        columns = 2;
      };
    }
    {
      "Local AI" = {
        style = "row";
        columns = 2;
      };
    }
    {
      "Productivity" = {
        style = "row";
        columns = 4;
      };
    }
    {
      "Standalone" = {
        style = "row";
        columns = 2;
      };
    }
    {
      "Shortcuts" = {
        style = "row";
        columns = 8;
      };
    }
    {
      "Dev Tools" = {
        style = "row";
        columns = 3;
      };
    }
    {
      "OTEL" = {
        style = "row";
        columns = 3;
      };
    }
    {
      "Datastores" = {
        style = "row";
        columns = 4;
      };
    }
    {
      "Infrastructure" = {
        style = "row";
        columns = 2;
      };
    }
  ];
}
