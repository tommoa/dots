{config, ...}: {
  # Arista status report pipeline scripts and skill
  # Scripts deployed to ~/bin/arista-report-*, shared lib to ~/lib/python/arista_report/
  age.secrets = {
    arista-report = {
      file = "${config.my.secretsPath}/arista-report/arista-report.age";
      path = "${config.home.homeDirectory}/bin/arista-report";
      mode = "0700";
    };
    arista-report-passrates = {
      file = "${config.my.secretsPath}/arista-report/arista-report-passrates.age";
      path = "${config.home.homeDirectory}/bin/arista-report-passrates";
      mode = "0700";
    };
    arista-report-bugs = {
      file = "${config.my.secretsPath}/arista-report/arista-report-bugs.age";
      path = "${config.home.homeDirectory}/bin/arista-report-bugs";
      mode = "0700";
    };
    arista-report-bugdetail = {
      file = "${config.my.secretsPath}/arista-report/arista-report-bugdetail.age";
      path = "${config.home.homeDirectory}/bin/arista-report-bugdetail";
      mode = "0700";
    };
    arista-report-merged = {
      file = "${config.my.secretsPath}/arista-report/arista-report-merged.age";
      path = "${config.home.homeDirectory}/bin/arista-report-merged";
      mode = "0700";
    };
    arista-report-reviews = {
      file = "${config.my.secretsPath}/arista-report/arista-report-reviews.age";
      path = "${config.home.homeDirectory}/bin/arista-report-reviews";
      mode = "0700";
    };
    arista-report-arastra = {
      file = "${config.my.secretsPath}/arista-report/arista-report-arastra.age";
      path = "${config.home.homeDirectory}/bin/arista-report-arastra";
      mode = "0700";
    };
    arista-report-merge = {
      file = "${config.my.secretsPath}/arista-report/arista-report-merge.age";
      path = "${config.home.homeDirectory}/bin/arista-report-merge";
      mode = "0700";
    };
    arista-report-format = {
      file = "${config.my.secretsPath}/arista-report/arista-report-format.age";
      path = "${config.home.homeDirectory}/bin/arista-report-format";
      mode = "0700";
    };
    arista-report-lib = {
      file = "${config.my.secretsPath}/arista-report/arista-report-lib.age";
      path = "${config.home.homeDirectory}/lib/python/arista_report/__init__.py";
      mode = "0644";
    };
    arista-status-report-skill = {
      file = "${config.my.secretsPath}/arista-report/arista-status-report-skill.age";
      path = "${config.home.homeDirectory}/.config/opencode/skill/arista-status-report/SKILL.md";
      mode = "0644";
    };
  };
}
