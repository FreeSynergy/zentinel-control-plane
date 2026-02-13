defmodule SentinelCpWeb.WafLiveTest do
  use SentinelCpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SentinelCp.{Analytics, Orgs, Projects, Accounts}

  setup do
    {:ok, org} = Orgs.create_org(%{name: "WAF Test Org", slug: "waf-test-org"})
    {:ok, project} = Projects.create_project(%{name: "WAF Test", slug: "waf-test", org_id: org.id})
    {:ok, user} = Accounts.register_user(%{email: "waf@test.com", password: "password123456"})
    Orgs.add_member(org, user, "admin")

    # Insert some WAF events
    events = [
      %{
        "project_id" => project.id,
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "rule_type" => "sqli",
        "action" => "blocked",
        "severity" => "high",
        "client_ip" => "10.0.0.1",
        "method" => "POST",
        "path" => "/api/users"
      }
    ]

    Analytics.ingest_waf_events(events)

    %{org: org, project: project, user: user}
  end

  test "renders WAF dashboard", %{conn: conn, project: project, user: user} do
    conn = log_in_user(conn, user)

    {:ok, view, html} =
      live(conn, ~p"/projects/#{project.slug}/waf")

    assert html =~ "WAF Events"
    assert html =~ "Total Events"
    assert html =~ "Blocked"
  end

  test "renders org-scoped WAF dashboard", %{conn: conn, org: org, project: project, user: user} do
    conn = log_in_user(conn, user)

    {:ok, _view, html} =
      live(conn, ~p"/orgs/#{org.slug}/projects/#{project.slug}/waf")

    assert html =~ "WAF Events"
  end
end
