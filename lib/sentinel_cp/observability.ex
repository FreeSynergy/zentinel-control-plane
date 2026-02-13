defmodule SentinelCp.Observability do
  @moduledoc """
  The Observability context manages SLOs, SLIs, alerting rules, and tracing.

  ## Features
  - SLO/SLI definition and computation
  - Alert rule evaluation with state machine
  - Telemetry-based tracing for key operations
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Observability.{Slo, SliComputer, AlertRule, AlertState}

  ## SLOs

  @doc "Creates a new SLO."
  def create_slo(attrs) do
    %Slo{}
    |> Slo.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an existing SLO."
  def update_slo(slo, attrs) do
    slo
    |> Slo.changeset(attrs)
    |> Repo.update()
  end

  @doc "Gets an SLO by ID."
  def get_slo(id), do: Repo.get(Slo, id)

  @doc "Lists all SLOs for a project."
  def list_slos(project_id) do
    from(s in Slo, where: s.project_id == ^project_id, order_by: [asc: s.name])
    |> Repo.all()
  end

  @doc "Lists enabled SLOs for a project."
  def list_enabled_slos(project_id) do
    from(s in Slo, where: s.project_id == ^project_id and s.enabled == true)
    |> Repo.all()
  end

  @doc "Deletes an SLO."
  def delete_slo(slo), do: Repo.delete(slo)

  @doc "Computes the current SLI for an SLO and updates the record."
  def compute_sli(slo), do: SliComputer.compute(slo)

  @doc "Computes SLIs for all enabled SLOs in a project."
  def compute_all_slis(project_id) do
    project_id
    |> list_enabled_slos()
    |> Enum.map(&SliComputer.compute/1)
  end

  ## Alert Rules

  @doc "Creates a new alert rule."
  def create_alert_rule(attrs) do
    %AlertRule{}
    |> AlertRule.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an alert rule."
  def update_alert_rule(rule, attrs) do
    rule
    |> AlertRule.changeset(attrs)
    |> Repo.update()
  end

  @doc "Gets an alert rule by ID."
  def get_alert_rule(id), do: Repo.get(AlertRule, id)

  @doc "Lists alert rules for a project."
  def list_alert_rules(project_id) do
    from(r in AlertRule, where: r.project_id == ^project_id, order_by: [asc: r.name])
    |> Repo.all()
  end

  @doc "Deletes an alert rule."
  def delete_alert_rule(rule), do: Repo.delete(rule)

  @doc "Silences an alert rule until the given datetime."
  def silence_alert_rule(rule, until) do
    rule
    |> AlertRule.changeset(%{silenced_until: until})
    |> Repo.update()
  end

  @doc "Removes silence from an alert rule."
  def unsilence_alert_rule(rule) do
    rule
    |> AlertRule.changeset(%{silenced_until: nil})
    |> Repo.update()
  end

  ## Alert States

  @doc "Gets the current active alert states for a rule."
  def active_alert_states(alert_rule_id) do
    from(s in AlertState,
      where: s.alert_rule_id == ^alert_rule_id and s.state in ["pending", "firing"],
      order_by: [desc: s.started_at]
    )
    |> Repo.all()
  end

  @doc "Gets alert state history for a rule."
  def alert_state_history(alert_rule_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(s in AlertState,
      where: s.alert_rule_id == ^alert_rule_id,
      order_by: [desc: s.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "Acknowledges a firing alert."
  def acknowledge_alert(alert_state, user_id) do
    alert_state
    |> AlertState.changeset(%{
      acknowledged_by: user_id,
      acknowledged_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc "Counts firing alerts for a project."
  def firing_alert_count(project_id) do
    from(s in AlertState,
      join: r in AlertRule,
      on: s.alert_rule_id == r.id,
      where: r.project_id == ^project_id and s.state == "firing"
    )
    |> Repo.aggregate(:count)
  end
end
