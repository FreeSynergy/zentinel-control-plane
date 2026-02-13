defmodule Mix.Tasks.Sentinel.Config.Export do
  @moduledoc """
  Exports a project's configuration as YAML or JSON.

  ## Usage

      mix sentinel.config.export <project_slug> [options]

  ## Options

    * `--format` - Output format: `yaml` (default) or `json`
    * `--output` - Write to file instead of stdout

  ## Examples

      mix sentinel.config.export my-project
      mix sentinel.config.export my-project --format json
      mix sentinel.config.export my-project --format yaml --output config.yaml
  """

  use Mix.Task

  @shortdoc "Export project configuration as YAML or JSON"

  @switches [format: :string, output: :string]
  @aliases [f: :format, o: :output]

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    case argv do
      [slug] ->
        Mix.Task.run("app.start")
        export(slug, opts)

      _ ->
        Mix.shell().error("Usage: mix sentinel.config.export <project_slug> [--format yaml|json] [--output file]")
        exit({:shutdown, 1})
    end
  end

  defp export(slug, opts) do
    format = Keyword.get(opts, :format, "yaml")
    output = Keyword.get(opts, :output)

    case SentinelCp.Projects.get_project_by_slug(slug) do
      nil ->
        Mix.shell().error("Project not found: #{slug}")
        exit({:shutdown, 1})

      project ->
        {:ok, config} = SentinelCp.ConfigExport.export(project.id)
        content = serialize(config, format)

        if output do
          File.write!(output, content)
          Mix.shell().info("Configuration exported to #{output}")
        else
          Mix.shell().info(content)
        end
    end
  end

  defp serialize(config, "json"), do: Jason.encode!(config, pretty: true)
  defp serialize(config, _), do: Ymlr.document!(config)
end
