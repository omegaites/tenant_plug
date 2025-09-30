defmodule TenantPlug.Sources.FromHeader do
  @moduledoc """
  Extracts tenant information from HTTP headers.

  This is the default tenant extraction source that looks for tenant information
  in HTTP request headers. By default, it looks for the "x-tenant-id" header,
  but this can be customized through configuration.

  ## Configuration Options

  * `:header` - The header name to look for (default: "x-tenant-id")
  * `:case_sensitive` - Whether header matching is case sensitive (default: false)
  * `:required` - Whether the header is required (default: false)
  * `:transform` - Optional function to transform the header value

  ## Examples

      # Default usage (looks for "x-tenant-id" header)
      plug TenantPlug, sources: [TenantPlug.Sources.FromHeader]

      # Custom header name
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromHeader, header: "tenant-id"}
      ]

      # Case sensitive matching
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromHeader, header: "X-Tenant-ID", case_sensitive: true}
      ]

      # Transform header value
      plug TenantPlug, sources: [
        {TenantPlug.Sources.FromHeader, 
         header: "x-tenant-id", 
         transform: &String.upcase/1}
      ]

  ## HTTP Request Examples

      # Standard usage
      GET /api/users
      X-Tenant-ID: tenant-123

      # Custom header
      GET /api/users  
      Tenant-ID: my-org

      # Multiple headers (first non-empty wins)
      GET /api/users
      X-Tenant-ID: 
      X-Client-ID: client-456  # This would be ignored
  """

  @behaviour TenantPlug.Sources.Behaviour

  @default_header "x-tenant-id"

  @doc """
  Extract tenant from HTTP headers.

  Looks for the configured header in the request and returns its value.
  """
  @impl TenantPlug.Sources.Behaviour
  def extract(conn, opts) do
    header_opts = get_header_opts(opts)
    header_name = header_opts[:header] || @default_header
    case_sensitive = header_opts[:case_sensitive] || false
    transform_fn = header_opts[:transform]

    header_value = get_header_value(conn, header_name, case_sensitive)

    case header_value do
      nil ->
        :not_found

      "" ->
        :not_found

      value ->
        transformed_value = 
          if transform_fn && is_function(transform_fn, 1) do
            try do
              transform_fn.(value)
            rescue
              error ->
                {:error, "Header transformation failed: #{inspect(error)}"}
            else
              result -> result
            end
          else
            value
          end

        case transformed_value do
          {:error, _} = error -> error
          transformed -> {:ok, transformed}
        end
    end
  end

  # Private functions

  defp get_header_opts(opts) do
    case Keyword.get(opts, :sources, []) do
      [] -> 
        []
      
      sources when is_list(sources) ->
        Enum.find_value(sources, [], fn
          {TenantPlug.Sources.FromHeader, source_opts} -> source_opts
          TenantPlug.Sources.FromHeader -> []
          _ -> nil
        end)
      
      _ ->
        # Return empty opts for malformed sources config
        []
    end
  end

  defp get_header_value(conn, header_name, case_sensitive) do
    headers = conn.req_headers

    if case_sensitive do
      case List.keyfind(headers, header_name, 0) do
        {^header_name, value} -> value
        nil -> nil
      end
    else
      lower_header = String.downcase(header_name)
      
      Enum.find_value(headers, fn {name, value} ->
        if String.downcase(name) == lower_header do
          value
        end
      end)
    end
  end

  @doc """
  Validate header configuration options.

  ## Examples

      iex> TenantPlug.Sources.FromHeader.validate_opts([])
      :ok

      iex> TenantPlug.Sources.FromHeader.validate_opts([header: "x-tenant"])
      :ok

      iex> TenantPlug.Sources.FromHeader.validate_opts([header: 123])
      {:error, ":header must be a string"}
  """
  @spec validate_opts(keyword()) :: :ok | {:error, String.t()}
  def validate_opts(opts) do
    with :ok <- validate_header(opts[:header]),
         :ok <- validate_case_sensitive(opts[:case_sensitive]),
         :ok <- validate_transform(opts[:transform]) do
      :ok
    end
  end

  defp validate_header(nil), do: :ok
  defp validate_header(header) when is_binary(header), do: :ok
  defp validate_header(_), do: {:error, ":header must be a string"}

  defp validate_case_sensitive(nil), do: :ok
  defp validate_case_sensitive(flag) when is_boolean(flag), do: :ok
  defp validate_case_sensitive(_), do: {:error, ":case_sensitive must be a boolean"}

  defp validate_transform(nil), do: :ok
  defp validate_transform(fun) when is_function(fun, 1), do: :ok
  defp validate_transform(_), do: {:error, ":transform must be a function of arity 1"}

  @doc """
  Get the default header name used by this source.

  ## Examples

      iex> TenantPlug.Sources.FromHeader.default_header()
      "x-tenant-id"
  """
  @spec default_header() :: String.t()
  def default_header, do: @default_header
end