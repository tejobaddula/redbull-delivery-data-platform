{#-
  Use the configured schema name verbatim (STAGING, MARTS) instead of dbt's
  default <target>_<custom> concatenation. Keeps Snowflake object names clean
  and matching snowflake/ddl/00_account_setup.sql.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
