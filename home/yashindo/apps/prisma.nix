{
  pkgs,
  lib,
  config,
  ...
}: let
  prismaEngines = pkgs.prisma-engines;
in {
  options.modules.prisma.enable = lib.mkEnableOption "Prisma engines";

  config = lib.mkIf config.modules.prisma.enable {
    home.packages = [prismaEngines];

    home.sessionVariables = {
      PRISMA_QUERY_ENGINE_LIBRARY = "${lib.getLib prismaEngines}/lib/libquery_engine.node";
      PRISMA_QUERY_ENGINE_BINARY = lib.getExe' prismaEngines "query-engine";
      PRISMA_SCHEMA_ENGINE_BINARY = lib.getExe' prismaEngines "schema-engine";
    };
  };
}
