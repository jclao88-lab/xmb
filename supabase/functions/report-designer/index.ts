import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const responseSchema = {
  type: "object",
  additionalProperties: false,
  required: ["title", "zh_title", "metrics", "dimensions", "filters", "parameters", "order_by", "limit", "visualization", "explanation"],
  properties: {
    title: { type: "string" },
    zh_title: { type: "string" },
    metrics: { type: "array", items: { type: "string" } },
    dimensions: { type: "array", items: { type: "string" } },
    filters: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["field", "operator", "value"],
        properties: {
          field: { type: "string" },
          operator: { type: "string", enum: ["=", ">=", "<="] },
          value: { type: "string" },
        },
      },
    },
    parameters: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["key", "label", "zh_label", "field", "operator", "input_type", "required", "options"],
        properties: {
          key: { type: "string" },
          label: { type: "string" },
          zh_label: { type: "string" },
          field: { type: "string" },
          operator: { type: "string", enum: ["=", ">=", "<="] },
          input_type: { type: "string", enum: ["text", "date", "select"] },
          required: { type: "boolean" },
          options: { type: "array", items: { type: "string" } },
        },
      },
    },
    order_by: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["metric", "direction"],
        properties: {
          metric: { type: "string" },
          direction: { type: "string", enum: ["asc", "desc"] },
        },
      },
    },
    limit: { type: "integer" },
    visualization: { type: "string", enum: ["table", "bar", "line"] },
    explanation: { type: "string" },
  },
};

type Provider = "openai" | "anthropic" | "google" | "custom_1" | "custom_2" | "custom_3";

type ModelConfig = {
  model_key: string;
  provider: Provider;
  provider_model_id: string;
  secret_name: string;
  endpoint_secret_name: string | null;
  supports_structured_output: boolean;
  allowed_roles: string[];
  is_active: boolean;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceRoleKey) throw new Error("AI report service is not configured.");

    const authHeader = request.headers.get("Authorization") || "";
    const authClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: userData, error: userError } = await authClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "Authentication is required." }, 401);

    const adminClient = createClient(url, serviceRoleKey);
    const { data: profile, error: profileError } = await adminClient
      .from("users")
      .select("id,role,is_active")
      .eq("id", userData.user.id)
      .single();
    if (profileError || !profile?.is_active || !["owner", "manager"].includes(profile.role)) {
      return json({ error: "This feature is available to owners and managers only." }, 403);
    }

    const body = await request.json();
    if (body.action === "delete_saved_report") {
      const reportId = String(body.report_id || "").trim();
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(reportId)) {
        return json({ error: "A valid report ID is required." }, 400);
      }
      const { data: deletedReport, error: deleteError } = await adminClient
        .from("saved_reports")
        .update({ is_active: false, updated_by: userData.user.id })
        .eq("id", reportId)
        .eq("created_by", userData.user.id)
        .eq("is_active", true)
        .select("id")
        .maybeSingle();
      if (deleteError) throw deleteError;
      if (!deletedReport) return json({ error: "Only the report creator can delete this report." }, 403);
      return json({ deleted: true, report_id: reportId }, 200);
    }

    const [metrics, dimensions, relationships, examples] = await Promise.all([
      adminClient.from("semantic_metrics").select("metric_key,zh_name,en_name,domain,result_type").eq("is_active", true),
      adminClient.from("semantic_dimensions").select("dimension_key,zh_name,en_name,domain,value_type").eq("is_active", true),
      adminClient.from("semantic_relationships").select("relationship_key,left_table,right_table,join_type").eq("is_active", true),
      adminClient.from("semantic_examples").select("zh_question,en_question,query_plan").eq("is_active", true).limit(12),
    ]);
    for (const result of [metrics, dimensions, relationships, examples]) if (result.error) throw result.error;

    if (body.action === "parameter_options") {
      const draft = validateDraft(body.draft, metrics.data || [], dimensions.data || []);
      const fields = [...new Set(draft.parameters.map((parameter) => parameter.field))]
        .filter((field) => !field.endsWith("_date"));
      const optionSets = new Map(fields.map((field) => [field, new Set<string>()]));
      for (const metric of draft.metrics) {
        const facts = await loadMetricFacts(adminClient, metric, fields);
        for (const fact of facts) {
          for (const field of fields) {
            const value = String(fact.dimensions[field] || "").trim();
            if (value) optionSets.get(field)?.add(value);
          }
        }
      }
      const options = Object.fromEntries([...optionSets].map(([field, values]) => [
        field,
        [...values].sort((left, right) => left.localeCompare(right)).slice(0, 200),
      ]));
      return json({ options }, 200);
    }

    if (body.action === "execute") {
      const draft = validateDraft(body.draft, metrics.data || [], dimensions.data || []);
      const startedAt = Date.now();
      try {
        const result = await executeControlledReport(adminClient, draft, metrics.data || [], dimensions.data || []);
        await adminClient.from("query_runs").insert({
          source_question: String(body.draft?.question || draft.title),
          query_plan: draft,
          result_summary: { row_count: result.rows.length, columns: result.columns.map((column) => column.key) },
          status: "temporary",
          duration_ms: Date.now() - startedAt,
          created_by: userData.user.id,
        });
        return json({ result }, 200);
      } catch (executionError) {
        await adminClient.from("query_runs").insert({
          source_question: String(body.draft?.question || draft.title),
          query_plan: draft,
          status: "failed",
          error_message: executionError instanceof Error ? executionError.message : "Report execution failed.",
          duration_ms: Date.now() - startedAt,
          created_by: userData.user.id,
        });
        throw executionError;
      }
    }

    if (body.action !== "design" || !String(body.question || "").trim() || !String(body.model_key || "").trim()) {
      return json({ error: "A report question and AI model are required." }, 400);
    }

    const { data: model, error: modelError } = await adminClient
      .from("ai_model_catalog")
      .select("model_key,provider,provider_model_id,secret_name,endpoint_secret_name,supports_structured_output,allowed_roles,is_active")
      .eq("model_key", body.model_key)
      .single();
    const selectedModel = model as ModelConfig | null;
    if (
      modelError ||
      !selectedModel?.is_active ||
      !selectedModel.allowed_roles.includes(profile.role) ||
      !selectedModel.supports_structured_output
    ) {
      return json({ error: "The selected AI model is not available." }, 403);
    }

    const apiKey = Deno.env.get(selectedModel.secret_name);
    if (!apiKey) throw new Error(`Missing server secret: ${selectedModel.secret_name}`);

    const catalog = { metrics: metrics.data, dimensions: dimensions.data, relationships: relationships.data, examples: examples.data };
    const prompt = `You design reusable, executable ERP report templates. Return one JSON object that follows the supplied schema. Use only metric_key and dimension_key values from this catalog. Do not write SQL. Respect the business domain explicitly requested by the user: purchasing reports must use purchase metrics with purchase order, supplier, and product dimensions; sales reports must use sales metrics with sales order, customer, and product dimensions; inventory reports must use inventory or stock movement metrics and compatible dimensions. Never reinterpret purchasing as sales or suppliers as customers. Additional requirements are mandatory. If they request aggregation, grouping, ranking, or a breakdown by a field, include that field in dimensions. For example, "按照供应商汇总" or "group by supplier" requires the supplier dimension. Use filters only for fixed conditions clearly requested by the user. Define useful optional runtime parameters so a saved report can be searched again, such as start date, end date, status, customer, supplier, product, country, or city. Every parameter.field must use a dimension_key compatible with every selected metric. Use separate >= and <= date parameters for date ranges. Use select only when you can provide controlled options; otherwise use text. Every order_by.metric must also appear in the metrics array. For rankings, set order_by and a reasonable limit. The report will be validated and compiled by a separate read-only service.\nCatalog:\n${JSON.stringify(catalog)}\nUser request:\n${String(body.question).trim()}\nAdditional requirements:\n${String(body.additional_requirements || "").trim() || "None"}`;
    const rawDraft = await callProvider(selectedModel, apiKey, prompt);
    const draft = applyExplicitReportGroupings(
      validateDraft(rawDraft, metrics.data || [], dimensions.data || []),
      `${String(body.question).trim()}\n${String(body.additional_requirements || "").trim()}`,
    );
    return json({ draft }, 200);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Report designer failed." }, 500);
  }
});

async function callProvider(model: ModelConfig, apiKey: string, prompt: string) {
  switch (model.provider) {
    case "openai":
      return callOpenAI(model.provider_model_id, apiKey, prompt);
    case "anthropic":
      return callAnthropic(model.provider_model_id, apiKey, prompt);
    case "google":
      return callGemini(model.provider_model_id, apiKey, prompt);
    case "custom_1":
    case "custom_2":
    case "custom_3":
      return callOpenAICompatible(model, apiKey, prompt);
    default:
      throw new Error("The selected AI provider is not configured.");
  }
}

async function callOpenAI(modelId: string, apiKey: string, prompt: string) {
  const payload = await fetchJson("OpenAI", "https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: modelId,
      input: prompt,
      text: { format: { type: "json_schema", name: "report_design", strict: true, schema: responseSchema } },
    }),
  });
  return parseJsonText(extractOpenAIText(payload), "OpenAI");
}

async function callAnthropic(modelId: string, apiKey: string, prompt: string) {
  const payload = await fetchJson("Claude", "https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: modelId,
      max_tokens: 2048,
      messages: [{ role: "user", content: prompt }],
      output_config: { format: { type: "json_schema", schema: responseSchema } },
    }),
  });
  const text = Array.isArray(payload.content)
    ? payload.content.filter((item: Record<string, unknown>) => item.type === "text").map((item: Record<string, unknown>) => item.text).join("")
    : "";
  return parseJsonText(text, "Claude");
}

async function callGemini(modelId: string, apiKey: string, prompt: string) {
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(modelId)}:generateContent`;
  const payload = await fetchJson("Gemini", endpoint, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { responseMimeType: "application/json", responseJsonSchema: responseSchema },
    }),
  });
  const parts = payload.candidates?.[0]?.content?.parts;
  const text = Array.isArray(parts) ? parts.map((part: Record<string, unknown>) => part.text || "").join("") : "";
  return parseJsonText(text, "Gemini");
}

async function callOpenAICompatible(model: ModelConfig, apiKey: string, prompt: string) {
  if (!model.endpoint_secret_name) throw new Error(`Missing endpoint secret name for ${model.provider}.`);
  const baseUrl = Deno.env.get(model.endpoint_secret_name);
  if (!baseUrl) throw new Error(`Missing server secret: ${model.endpoint_secret_name}`);
  const endpoint = buildCompatibleEndpoint(baseUrl);
  const payload = await fetchJson(model.provider, endpoint, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: model.provider_model_id,
      messages: [{ role: "user", content: prompt }],
      response_format: { type: "json_schema", json_schema: { name: "report_design", strict: true, schema: responseSchema } },
    }),
  });
  const content = payload.choices?.[0]?.message?.content;
  const text = typeof content === "string"
    ? content
    : Array.isArray(content)
      ? content.map((item: Record<string, unknown>) => item.text || "").join("")
      : "";
  return parseJsonText(text, model.provider);
}

function buildCompatibleEndpoint(rawBaseUrl: string) {
  const url = new URL(rawBaseUrl);
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) {
    throw new Error("Custom provider Base URL must be a clean HTTPS URL.");
  }
  const path = url.pathname.replace(/\/+$/, "");
  if (!path.endsWith("/chat/completions")) url.pathname = `${path}/chat/completions`;
  return url.toString();
}

async function fetchJson(provider: string, endpoint: string, init: RequestInit) {
  const response = await fetch(endpoint, { ...init, signal: AbortSignal.timeout(45_000) });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 1500);
    console.error(`${provider} request failed (${response.status}): ${detail}`);
    throw new Error(`${provider} request failed (${response.status}): ${extractProviderError(detail)}`);
  }
  return response.json();
}

function extractProviderError(detail: string) {
  try {
    const payload = JSON.parse(detail);
    const message = payload?.error?.message || payload?.message;
    if (message) return String(message).replace(/[\r\n]+/g, " ").slice(0, 500);
  } catch {
    // Some OpenAI-compatible providers return plain-text errors.
  }
  return detail.replace(/[\r\n]+/g, " ").slice(0, 500) || "Unknown provider error";
}

function extractOpenAIText(payload: Record<string, any>) {
  if (typeof payload.output_text === "string") return payload.output_text;
  if (!Array.isArray(payload.output)) return "";
  return payload.output
    .flatMap((item: Record<string, any>) => Array.isArray(item.content) ? item.content : [])
    .map((item: Record<string, any>) => item.text || "")
    .join("");
}

function parseJsonText(text: unknown, provider: string) {
  if (typeof text !== "string" || !text.trim()) throw new Error(`${provider} returned no report definition.`);
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${provider} returned an invalid JSON report definition.`);
  }
}

type ReportDraft = {
  title: string;
  zh_title: string;
  metrics: string[];
  dimensions: string[];
  filters: Array<{ field: string; operator: "=" | ">=" | "<="; value: string }>;
  parameters: Array<{
    key: string;
    label: string;
    zh_label: string;
    field: string;
    operator: "=" | ">=" | "<=";
    input_type: "text" | "date" | "select";
    required: boolean;
    options: string[];
  }>;
  order_by: Array<{ metric: string; direction: "asc" | "desc" }>;
  limit: number;
  visualization: "table" | "bar" | "line";
  explanation: string;
};

type MetricFact = {
  dimensions: Record<string, string>;
  value: number;
  distinctId?: string;
};

const MAX_SOURCE_ROWS = 10_000;
const PAGE_SIZE = 1_000;

async function executeControlledReport(
  client: any,
  draft: ReportDraft,
  metricCatalog: Record<string, unknown>[],
  dimensionCatalog: Record<string, unknown>[],
) {
  const rowsByGroup = new Map<string, Record<string, string | number>>();

  for (const metric of draft.metrics) {
    const requiredDimensions = [...new Set([...draft.dimensions, ...draft.filters.map((filter) => filter.field)])];
    const facts = (await loadMetricFacts(client, metric, requiredDimensions)).filter((fact) => matchesFilters(fact, draft.filters));
    const groups = new Map<string, { dimensions: Record<string, string>; value: number; ids: Set<string> }>();

    for (const fact of facts) {
      const selected = Object.fromEntries(draft.dimensions.map((key) => [key, fact.dimensions[key] || "(Blank)"]));
      const groupKey = JSON.stringify(selected);
      const group = groups.get(groupKey) || { dimensions: selected, value: 0, ids: new Set<string>() };
      if (fact.distinctId) {
        if (!group.ids.has(fact.distinctId)) {
          group.ids.add(fact.distinctId);
          group.value += fact.value;
        }
      } else {
        group.value += fact.value;
      }
      groups.set(groupKey, group);
    }

    if (!facts.length && !draft.dimensions.length) groups.set("{}", { dimensions: {}, value: 0, ids: new Set<string>() });
    for (const [groupKey, group] of groups) {
      const row = rowsByGroup.get(groupKey) || { ...group.dimensions };
      row[metric] = roundNumber(group.value);
      rowsByGroup.set(groupKey, row);
    }
  }

  const order = draft.order_by[0] || { metric: draft.metrics[0], direction: "desc" as const };
  const rows = [...rowsByGroup.values()]
    .map((row) => {
      for (const metric of draft.metrics) if (row[metric] === undefined) row[metric] = 0;
      return row;
    })
    .sort((left, right) => (Number(left[order.metric] || 0) - Number(right[order.metric] || 0)) * (order.direction === "asc" ? 1 : -1))
    .slice(0, draft.limit);

  const dimensionNames = new Map(dimensionCatalog.map((item) => [String(item.dimension_key), String(item.en_name || item.dimension_key)]));
  const metricNames = new Map(metricCatalog.map((item) => [String(item.metric_key), String(item.en_name || item.metric_key)]));
  return {
    title: draft.title,
    zh_title: draft.zh_title,
    visualization: draft.visualization,
    columns: [
      ...draft.dimensions.map((key) => ({ key, label: dimensionNames.get(key) || key, type: "dimension" })),
      ...draft.metrics.map((key) => ({ key, label: metricNames.get(key) || key, type: "metric" })),
    ],
    rows,
  };
}

async function loadMetricFacts(client: any, metric: string, dimensions: string[]): Promise<MetricFact[]> {
  const needsProduct = dimensions.includes("product") || dimensions.includes("product_category");
  const salesDimensions = ["sales_order_date", "customer", "customer_country", "customer_city", "sales_order_status", "product", "product_category"];
  const purchaseDimensions = ["purchase_order_date", "supplier", "purchase_order_status", "product", "product_category"];
  const inventoryDimensions = ["product", "product_category"];
  const movementDimensions = ["product", "product_category", "stock_movement_date", "stock_movement_type"];

  if (["sales_amount", "sales_order_count", "sales_quantity", "estimated_gross_profit"].includes(metric)) {
    assertDimensions(dimensions, salesDimensions, metric);
    const itemMode = needsProduct || ["sales_quantity", "estimated_gross_profit"].includes(metric);
    if (itemMode) {
      const rows = await fetchAll((from, to) => client.from("sales_order_items")
        .select("quantity,line_amount,sales_order:sales_orders(id,order_date,status,customer:customers(id,name,zh_name,country,city)),product:products(id,sku,name,zh_name,category,cost_price)")
        .range(from, to));
      return rows.map((row: any) => {
        const order = relation(row.sales_order);
        const customer = relation(order.customer);
        const product = relation(row.product);
        const value = metric === "sales_order_count" ? 1
          : metric === "sales_quantity" ? numberValue(row.quantity)
          : metric === "estimated_gross_profit" ? numberValue(row.line_amount) - numberValue(row.quantity) * numberValue(product.cost_price)
          : numberValue(row.line_amount);
        return {
          dimensions: salesFactDimensions(order, customer, product),
          value,
          distinctId: metric === "sales_order_count" ? String(order.id || "") : undefined,
        };
      });
    }
    const rows = await fetchAll((from, to) => client.from("sales_orders")
      .select("id,order_date,status,total_amount,customer:customers(id,name,zh_name,country,city)")
      .range(from, to));
    return rows.map((row: any) => ({
      dimensions: salesFactDimensions(row, relation(row.customer), {}),
      value: metric === "sales_order_count" ? 1 : numberValue(row.total_amount),
      distinctId: metric === "sales_order_count" ? String(row.id) : undefined,
    }));
  }

  if (["purchase_amount", "purchase_quantity"].includes(metric)) {
    assertDimensions(dimensions, purchaseDimensions, metric);
    const rows = await fetchAll((from, to) => client.from("purchase_order_items")
      .select("quantity,line_amount,purchase_order:purchase_orders(id,order_date,status,supplier:suppliers(id,name,zh_name)),product:products(id,sku,name,zh_name,category)")
      .range(from, to));
    return rows.map((row: any) => {
      const order = relation(row.purchase_order);
      const supplier = relation(order.supplier);
      const product = relation(row.product);
      return {
        dimensions: {
          purchase_order_date: dateValue(order.order_date),
          supplier: entityLabel(supplier),
          purchase_order_status: String(order.status || ""),
          product: entityLabel(product),
          product_category: String(product.category || ""),
        },
        value: metric === "purchase_quantity" ? numberValue(row.quantity) : numberValue(row.line_amount),
      };
    });
  }

  if (["stock_quantity", "low_stock_item_count"].includes(metric)) {
    assertDimensions(dimensions, inventoryDimensions, metric);
    const rows = await fetchAll((from, to) => client.from("inventory")
      .select("quantity,product:products(id,sku,name,zh_name,category,min_stock)")
      .range(from, to));
    return rows.flatMap((row: any) => {
      const product = relation(row.product);
      if (metric === "low_stock_item_count" && numberValue(row.quantity) >= numberValue(product.min_stock)) return [];
      return [{
        dimensions: { product: entityLabel(product), product_category: String(product.category || "") },
        value: metric === "low_stock_item_count" ? 1 : numberValue(row.quantity),
      }];
    });
  }

  if (["inbound_quantity", "outbound_quantity"].includes(metric)) {
    assertDimensions(dimensions, movementDimensions, metric);
    const rows = await fetchAll((from, to) => client.from("stock_movements")
      .select("id,created_at,movement_type,quantity_change,product:products(id,sku,name,zh_name,category)")
      .range(from, to));
    return rows.flatMap((row: any) => {
      const quantity = numberValue(row.quantity_change);
      if (metric === "inbound_quantity" && quantity <= 0) return [];
      if (metric === "outbound_quantity" && quantity >= 0) return [];
      const product = relation(row.product);
      return [{
        dimensions: {
          product: entityLabel(product),
          product_category: String(product.category || ""),
          stock_movement_date: dateValue(row.created_at),
          stock_movement_type: String(row.movement_type || ""),
        },
        value: Math.abs(quantity),
      }];
    });
  }

  throw new Error(`Metric ${metric} is not available in the controlled executor.`);
}

async function fetchAll(fetchPage: (from: number, to: number) => PromiseLike<any>) {
  const rows: any[] = [];
  for (let from = 0; from < MAX_SOURCE_ROWS; from += PAGE_SIZE) {
    const { data, error } = await fetchPage(from, from + PAGE_SIZE - 1);
    if (error) throw error;
    const page = data || [];
    rows.push(...page);
    if (page.length < PAGE_SIZE) return rows;
  }
  throw new Error(`Report source exceeds the ${MAX_SOURCE_ROWS}-row execution limit.`);
}

function salesFactDimensions(order: any, customer: any, product: any) {
  return {
    sales_order_date: dateValue(order.order_date),
    customer: entityLabel(customer),
    customer_country: String(customer.country || ""),
    customer_city: String(customer.city || ""),
    sales_order_status: String(order.status || ""),
    product: entityLabel(product),
    product_category: String(product.category || ""),
  };
}

function matchesFilters(fact: MetricFact, filters: ReportDraft["filters"]) {
  return filters.every((filter) => {
    const actual = fact.dimensions[filter.field];
    if (actual === undefined) return true;
    if (filter.operator === "=") return actual.toLowerCase() === filter.value.toLowerCase();
    if (filter.operator === ">=") return actual >= filter.value;
    return actual <= filter.value;
  });
}

function assertDimensions(selected: string[], allowed: string[], metric: string) {
  const invalid = selected.find((key) => !allowed.includes(key));
  if (invalid) throw new Error(`Dimension ${invalid} cannot be used with metric ${metric}.`);
}

function relation(value: any) {
  return Array.isArray(value) ? value[0] || {} : value || {};
}

function entityLabel(entity: any) {
  return String(entity.zh_name || entity.name || entity.sku || entity.id || "");
}

function dateValue(value: unknown) {
  return String(value || "").slice(0, 10);
}

function numberValue(value: unknown) {
  const number = Number(value || 0);
  return Number.isFinite(number) ? number : 0;
}

function roundNumber(value: number) {
  return Math.round((value + Number.EPSILON) * 1000) / 1000;
}

function validateDraft(raw: Record<string, unknown>, metrics: Record<string, unknown>[], dimensions: Record<string, unknown>[]): ReportDraft {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("The AI report definition is invalid.");
  const metricKeys = new Set(metrics.map((item) => String(item.metric_key)));
  const dimensionKeys = new Set(dimensions.map((item) => String(item.dimension_key)));
  const selectedMetrics = validateKeyList(raw.metrics, metricKeys, "metric", 1, 8);
  const compatibleDimensions = compatibleDimensionKeys(selectedMetrics);
  const selectedDimensions = validateKeyList(raw.dimensions, dimensionKeys, "dimension", 0, 4).filter((key) => compatibleDimensions.has(key));
  const filters = validateFilters(raw.filters, dimensionKeys).filter((filter) => compatibleDimensions.has(filter.field));
  const parameters = validateParameters(raw.parameters, dimensionKeys).filter((parameter) => compatibleDimensions.has(parameter.field));
  const orderBy = validateOrderBy(raw.order_by, new Set(selectedMetrics));
  const requestedLimit = Number(raw.limit || 50);
  const limit = Number.isInteger(requestedLimit) ? Math.min(100, Math.max(1, requestedLimit)) : 50;
  const visualization = String(raw.visualization || "");
  if (!["table", "bar", "line"].includes(visualization)) throw new Error("The AI selected an unsupported visualization.");
  const normalizedText = normalizeReportDomainText(
    selectedMetrics,
    validateText(raw.title || raw.question || "Report", "title", 200),
    validateText(raw.zh_title || raw.title || raw.question || "报表", "Chinese title", 200),
    validateText(raw.explanation || "Controlled report", "explanation", 2000),
  );

  return {
    title: normalizedText.title,
    zh_title: normalizedText.zhTitle,
    metrics: selectedMetrics,
    dimensions: selectedDimensions,
    filters,
    parameters,
    order_by: orderBy,
    limit,
    visualization: visualization as "table" | "bar" | "line",
    explanation: normalizedText.explanation,
  };
}

function normalizeReportDomainText(metrics: string[], title: string, zhTitle: string, explanation: string) {
  const isPurchaseOnly = metrics.length > 0 && metrics.every((metric) => ["purchase_amount", "purchase_quantity"].includes(metric));
  const isSalesOnly = metrics.length > 0 && metrics.every((metric) => ["sales_amount", "sales_order_count", "sales_quantity", "estimated_gross_profit"].includes(metric));
  const isInventoryOnly = metrics.length > 0 && metrics.every((metric) => ["stock_quantity", "low_stock_item_count", "inbound_quantity", "outbound_quantity"].includes(metric));
  const combinedTitle = `${title} ${zhTitle}`;
  if (isPurchaseOnly && /sales|customer|vip|销售|客户/i.test(combinedTitle)) {
    title = "Purchasing Report";
    zhTitle = "采购报表";
  }
  if (isSalesOnly && /purchase|supplier|采购|供应商/i.test(combinedTitle)) {
    title = "Sales Report";
    zhTitle = "销售报表";
  }
  if (isInventoryOnly && /sales|customer|purchase|supplier|销售|客户|采购|供应商/i.test(combinedTitle)) {
    title = "Inventory Report";
    zhTitle = "库存报表";
  }
  if (isPurchaseOnly && /sales|customer|销售|客户/i.test(explanation)) explanation = "This report retrieves purchasing data using the selected metrics, dimensions, and optional criteria.";
  if (isSalesOnly && /purchase|supplier|采购|供应商/i.test(explanation)) explanation = "This report retrieves sales data using the selected metrics, dimensions, and optional criteria.";
  if (isInventoryOnly && /sales|customer|purchase|supplier|销售|客户|采购|供应商/i.test(explanation)) explanation = "This report retrieves inventory data using the selected metrics, dimensions, and optional criteria.";
  return { title, zhTitle, explanation };
}

function applyExplicitReportGroupings(draft: ReportDraft, requestText: string) {
  const groupingRules: Array<{ field: string; pattern: RegExp }> = [
    { field: "supplier", pattern: /按(?:照)?\s*供应商(?:汇总|统计|分组|排行|输出)?|供应商(?:汇总|统计|分组)|(?:group|grouped|summarize|summarized|aggregate|aggregated|breakdown)\s+by\s+(?:the\s+)?supplier|\bby supplier\b/i },
    { field: "customer", pattern: /按(?:照)?\s*客户(?:汇总|统计|分组|排行|输出)?|客户(?:汇总|统计|分组)|(?:group|grouped|summarize|summarized|aggregate|aggregated|breakdown)\s+by\s+(?:the\s+)?customer|\bby customer\b/i },
    { field: "product", pattern: /按(?:照)?\s*(?:产品|商品)(?:汇总|统计|分组|排行|输出)?|(?:产品|商品)(?:汇总|统计|分组)|(?:group|grouped|summarize|summarized|aggregate|aggregated|breakdown)\s+by\s+(?:the\s+)?product|\bby product\b/i },
    { field: "product_category", pattern: /按(?:照)?\s*(?:产品|商品)?分类(?:汇总|统计|分组|排行|输出)?|(?:产品|商品)分类(?:汇总|统计|分组)|(?:group|grouped|summarize|summarized|aggregate|aggregated|breakdown)\s+by\s+(?:the\s+)?(?:product\s+)?category|\bby (?:product )?category\b/i },
  ];
  const compatible = compatibleDimensionKeys(draft.metrics);
  const requested = groupingRules.filter((rule) => rule.pattern.test(requestText) && compatible.has(rule.field)).map((rule) => rule.field);
  if (!requested.length) return draft;
  return { ...draft, dimensions: [...new Set([...requested, ...draft.dimensions])].slice(0, 4) };
}

function compatibleDimensionKeys(metrics: string[]) {
  const dimensionsByMetric: Record<string, string[]> = {
    sales_amount: ["sales_order_date", "customer", "customer_country", "customer_city", "sales_order_status", "product", "product_category"],
    sales_order_count: ["sales_order_date", "customer", "customer_country", "customer_city", "sales_order_status", "product", "product_category"],
    sales_quantity: ["sales_order_date", "customer", "customer_country", "customer_city", "sales_order_status", "product", "product_category"],
    estimated_gross_profit: ["sales_order_date", "customer", "customer_country", "customer_city", "sales_order_status", "product", "product_category"],
    purchase_amount: ["purchase_order_date", "supplier", "purchase_order_status", "product", "product_category"],
    purchase_quantity: ["purchase_order_date", "supplier", "purchase_order_status", "product", "product_category"],
    stock_quantity: ["product", "product_category"],
    low_stock_item_count: ["product", "product_category"],
    inbound_quantity: ["stock_movement_date", "stock_movement_type", "product", "product_category"],
    outbound_quantity: ["stock_movement_date", "stock_movement_type", "product", "product_category"],
  };
  const supported = metrics.map((metric) => dimensionsByMetric[metric]).filter(Boolean);
  return new Set(supported.length ? supported[0].filter((field) => supported.every((list) => list.includes(field))) : []);
}

function validateParameters(value: unknown, allowedFields: Set<string>): ReportDraft["parameters"] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) return [];
  const usedKeys = new Set<string>();
  return value.slice(0, 10).flatMap((item) => {
    const parameter = item as Record<string, unknown>;
    const key = String(parameter.key || "").trim().replace(/[^a-zA-Z0-9_]/g, "_").slice(0, 60);
    const field = String(parameter.field || "");
    const operator = String(parameter.operator || "");
    const inputType = String(parameter.input_type || "");
    const label = String(parameter.label || key).trim().slice(0, 100);
    const zhLabel = String(parameter.zh_label || label).trim().slice(0, 100);
    if (
      !key ||
      usedKeys.has(key) ||
      !allowedFields.has(field) ||
      !["=", ">=", "<="].includes(operator) ||
      !["text", "date", "select"].includes(inputType) ||
      (inputType === "date" && !field.endsWith("_date")) ||
      (operator !== "=" && inputType !== "date")
    ) {
      return [];
    }
    const options = Array.isArray(parameter.options) ? parameter.options.map(String).map((option) => option.trim()).filter(Boolean).slice(0, 30) : [];
    if (inputType === "select" && !options.length) return [];
    usedKeys.add(key);
    return [{
      key,
      label,
      zh_label: zhLabel,
      field,
      operator: operator as "=" | ">=" | "<=",
      input_type: inputType as "text" | "date" | "select",
      required: Boolean(parameter.required),
      options,
    }];
  });
}

function validateFilters(value: unknown, allowedFields: Set<string>): ReportDraft["filters"] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 18) throw new Error("The AI selected an invalid filter list.");
  return value.map((item) => {
    const filter = item as Record<string, unknown>;
    const field = String(filter.field || "");
    const operator = String(filter.operator || "");
    const filterValue = String(filter.value || "").trim();
    if (!allowedFields.has(field) || !["=", ">=", "<="].includes(operator) || !filterValue) {
      throw new Error("The AI selected an unsupported report filter.");
    }
    return { field, operator: operator as "=" | ">=" | "<=", value: filterValue };
  });
}

function validateOrderBy(value: unknown, selectedMetrics: Set<string>): ReportDraft["order_by"] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) return [];
  return value.slice(0, 2).flatMap((item) => {
    const order = item as Record<string, unknown>;
    const metric = String(order.metric || "");
    const direction = String(order.direction || "").toLowerCase();
    if (!selectedMetrics.has(metric) || !["asc", "desc"].includes(direction)) {
      return [];
    }
    return [{ metric, direction: direction as "asc" | "desc" }];
  });
}

function validateKeyList(value: unknown, allowed: Set<string>, label: string, min: number, max: number) {
  if (!Array.isArray(value) || value.length < min || value.length > max) {
    throw new Error(`The AI selected an invalid ${label} list.`);
  }
  const result = [...new Set(value.map(String))];
  if (result.some((key) => !allowed.has(key))) throw new Error(`The AI selected an unknown ${label}.`);
  return result;
}

function validateText(value: unknown, label: string, maxLength: number) {
  const text = String(value || "").trim();
  if (!text || text.length > maxLength) throw new Error(`The AI returned an invalid ${label}.`);
  return text;
}

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
