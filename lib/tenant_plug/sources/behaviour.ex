defmodule TenantPlug.Sources.Behaviour do
  @moduledoc """
  Behaviour for tenant extraction sources.

  This module defines the interface that all tenant extraction sources must implement.
  Sources are responsible for extracting tenant information from HTTP requests using
  different strategies (headers, subdomains, JWT tokens, etc.).

  ## Example Implementation

      defmodule MyApp.CustomTenantSource do
        @behaviour TenantPlug.Sources.Behaviour

        @impl TenantPlug.Sources.Behaviour
        def extract(conn, opts) do
          case get_tenant_from_custom_logic(conn) do
            nil -> :not_found
            tenant -> {:ok, tenant}
          end
        rescue
          error -> {:error, error}
        end

        defp get_tenant_from_custom_logic(conn) do
          # Your custom extraction logic here
        end
      end

  ## Return Values

  Sources should return one of the following:

  * `{:ok, tenant}` - Successfully extracted a tenant
  * `{:ok, nil}` - No tenant found, but no error occurred  
  * `:not_found` - No tenant found (equivalent to `{:ok, nil}`)
  * `{:error, reason}` - An error occurred during extraction

  ## Error Handling

  If a source raises an exception, TenantPlug will catch it and continue
  to the next source in the chain. Sources should prefer returning
  `{:error, reason}` over raising exceptions when possible.

  ## Options

  The `opts` parameter contains the full configuration passed to TenantPlug,
  including any source-specific options. Sources should document their
  supported options.
  """

  @doc """
  Extract tenant information from the given connection.

  ## Parameters

  * `conn` - The `Plug.Conn` struct representing the current HTTP request
  * `opts` - Configuration options passed to TenantPlug

  ## Returns

  * `{:ok, tenant}` - Successfully extracted a tenant (tenant can be any term)
  * `{:ok, nil}` - No tenant found, but no error occurred
  * `:not_found` - No tenant found (equivalent to `{:ok, nil}`)
  * `{:error, reason}` - An error occurred during extraction

  ## Examples

      # Successful extraction
      {:ok, "tenant-123"}

      # No tenant found
      :not_found
      # or
      {:ok, nil}

      # Error during extraction
      {:error, "Invalid tenant format"}
  """
  @callback extract(conn :: Plug.Conn.t(), opts :: keyword()) ::
    {:ok, term()} | {:ok, nil} | :not_found | {:error, term()}
end