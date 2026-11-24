{#
  本番(prod)だけ staging / marts のデータセットに分けて作る。
  dev と ci は target の dataset 1つにまとめる（本番を汚さないため）。
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name == 'prod' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
