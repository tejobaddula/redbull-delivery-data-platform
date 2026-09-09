{#- blank/whitespace-only string -> NULL -#}
{% macro nullify_blank(col) -%}
    NULLIF(TRIM({{ col }}), '')
{%- endmacro %}

{#- collapse embedded newlines / repeated whitespace to a single space, then blank -> NULL -#}
{% macro collapse_ws(col) -%}
    NULLIF(TRIM(REGEXP_REPLACE({{ col }}, '\\s+', ' ')), '')
{%- endmacro %}

{#- '0'/'1'/'true'/'false'/'t'/'f' (any case) -> BOOLEAN, else NULL -#}
{% macro to_bool(col) -%}
    CASE LOWER(TRIM({{ col }}))
        WHEN '1' THEN TRUE  WHEN 'true'  THEN TRUE  WHEN 't' THEN TRUE
        WHEN '0' THEN FALSE WHEN 'false' THEN FALSE WHEN 'f' THEN FALSE
        ELSE NULL
    END
{%- endmacro %}

{#- safe numeric cast from a possibly-blank string -#}
{% macro to_number(col, precision=38, scale=4) -%}
    TRY_CAST({{ nullify_blank(col) }} AS NUMBER({{ precision }}, {{ scale }}))
{%- endmacro %}

{% macro to_float(col) -%}
    TRY_CAST({{ nullify_blank(col) }} AS FLOAT)
{%- endmacro %}

{% macro to_int(col) -%}
    TRY_CAST({{ nullify_blank(col) }} AS INTEGER)
{%- endmacro %}

{% macro to_date(col) -%}
    TRY_TO_DATE({{ nullify_blank(col) }})
{%- endmacro %}
