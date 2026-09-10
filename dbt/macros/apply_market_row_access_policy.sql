{#-
  Attach UTIL.RAP_MARKET to `relation` on its market_code column, unless already attached.
  Used as a +post-hook on MARTS models that carry market_code — dbt rebuilds tables with
  CREATE OR REPLACE, which drops policy attachments, so we re-assert after every build.
  The policy itself is created once by snowflake/ddl/03_row_access_policies.sql.
-#}
{% macro apply_market_row_access_policy(relation) %}
    {%- if not execute -%}{{ return('') }}{%- endif -%}

    {%- set check_sql -%}
        select count(*) as n
        from table(information_schema.policy_references(
            ref_entity_name   => '{{ relation }}',
            ref_entity_domain => 'table'))
        where policy_kind = 'ROW_ACCESS_POLICY'
          and policy_name  = 'RAP_MARKET'
    {%- endset -%}

    {%- set already = run_query(check_sql).columns[0].values()[0] -%}

    {%- if already and already | int > 0 -%}
        {{ log("RAP_MARKET already on " ~ relation, info=false) }}
        select 1
    {%- else -%}
        alter table {{ relation }}
        add row access policy REDBULL_DELIVERY.UTIL.RAP_MARKET on (market_code)
    {%- endif -%}
{% endmacro %}
