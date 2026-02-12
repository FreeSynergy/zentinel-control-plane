defmodule SentinelCpWeb.CertificatesLive.New do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        {:ok,
         assign(socket,
           page_title: "Upload Certificate — #{project.name}",
           org: org,
           project: project
         )}
    end
  end

  @impl true
  def handle_event("create_certificate", params, socket) do
    project = socket.assigns.project

    attrs = %{
      project_id: project.id,
      name: params["name"],
      domain: params["domain"],
      cert_pem: params["cert_pem"],
      key_pem: params["key_pem"],
      ca_chain_pem: blank_to_nil(params["ca_chain_pem"]),
      auto_renew: params["auto_renew"] == "true"
    }

    case Services.create_certificate(attrs) do
      {:ok, cert} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "certificate", cert.id,
          project_id: project.id
        )

        show_path = cert_show_path(socket.assigns.org, project, cert)

        {:noreply,
         socket
         |> put_flash(:info, "Certificate uploaded.")
         |> push_navigate(to: show_path)}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 max-w-2xl">
      <h1 class="text-xl font-bold">Upload Certificate</h1>

      <.k8s_section>
        <form phx-submit="create_certificate" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. API TLS Cert"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Domain</span></label>
            <input
              type="text"
              name="domain"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. api.example.com"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">Primary domain for this certificate (also extracted from PEM)</span>
            </label>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Certificate PEM</span></label>
            <textarea
              name="cert_pem"
              required
              rows="8"
              class="textarea textarea-bordered textarea-sm w-full font-mono"
              placeholder="-----BEGIN CERTIFICATE-----&#10;...&#10;-----END CERTIFICATE-----"
            ></textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Private Key PEM</span></label>
            <textarea
              name="key_pem"
              required
              rows="8"
              class="textarea textarea-bordered textarea-sm w-full font-mono"
              placeholder="-----BEGIN PRIVATE KEY-----&#10;...&#10;-----END PRIVATE KEY-----"
            ></textarea>
            <label class="label">
              <span class="label-text-alt text-base-content/50">
                The private key is encrypted at rest and never leaves the control plane in plaintext.
              </span>
            </label>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">CA Chain PEM (optional)</span></label>
            <textarea
              name="ca_chain_pem"
              rows="6"
              class="textarea textarea-bordered textarea-sm w-full font-mono"
              placeholder="-----BEGIN CERTIFICATE-----&#10;...&#10;-----END CERTIFICATE-----"
            ></textarea>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer gap-2 justify-start">
              <input type="checkbox" name="auto_renew" value="true" class="checkbox checkbox-sm" />
              <span class="label-text font-medium">Enable Auto-Renew</span>
            </label>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Upload Certificate</button>
            <.link navigate={certs_path(@org, @project)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp certs_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/certificates"

  defp certs_path(nil, project),
    do: ~p"/projects/#{project.slug}/certificates"

  defp cert_show_path(%{slug: org_slug}, project, cert),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/certificates/#{cert.id}"

  defp cert_show_path(nil, project, cert),
    do: ~p"/projects/#{project.slug}/certificates/#{cert.id}"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(str), do: str
end
