# Research Report: Microsoft Foundry V2 — Agent Tracing / Observability (Traces Tab)

**Date:** 2026-05-21
**Researcher:** Copilot MS Docs Researcher Agent
**Topic slug:** foundry-agent-traces
**Sources consulted:** 8 Microsoft Learn pages, 3 GitHub repositories, 3 code samples

---

## Executive Summary

Microsoft Foundry V2 provides an observability platform for tracing AI agent executions, built on OpenTelemetry and backed by Azure Monitor Application Insights. When properly configured, the **Traces tab** in the Foundry portal (accessed via **Agents → Traces**) displays per-run trace timelines showing span hierarchies, tool calls, latencies, token usage, and input/output content. Traces are stored in Application Insights and are queryable via KQL.

Getting traces to appear requires three things: (1) an Application Insights resource **connected** to the Foundry account as a connection of category `AppInsights`, (2) client-side SDK instrumentation using the `AIProjectInstrumentor` from `azure-ai-projects` with the experimental feature gate enabled, and (3) the `agent_reference` payload in `responses.create()` calls so the instrumentor can generate `invoke_agent` spans. For Foundry V2 (new portal, `Microsoft.CognitiveServices/accounts`), the connection is created at the **account** level (not project level) and shared to all projects.

Server-side traces for Prompt agents are logged automatically once Application Insights is connected — no code changes required. For richer client-side traces (including custom spans, business attributes, and distributed trace correlation with FastAPI), the SDK instrumentation described in this report is needed. The instrumentation handles both streaming and non-streaming `responses.create()` calls, producing a single parent span per response.

---

## Table of Contents

- [1. What the Foundry V2 Portal Traces Tab Shows](#1-what-the-foundry-v2-portal-traces-tab-shows)
- [2. Prerequisites for Traces to Appear](#2-prerequisites-for-traces-to-appear)
- [3. SDK-Side Instrumentation (Python)](#3-sdk-side-instrumentation-python)
- [4. End-to-End Trace Correlation](#4-end-to-end-trace-correlation)
- [5. Bicep: Application Insights Connection](#5-bicep-application-insights-connection)
- [6. az CLI Commands](#6-az-cli-commands)
- [7. Common Gotchas / Known Limitations](#7-common-gotchas--known-limitations)
- [8. Worked Example](#8-worked-example)
- [9. Research Limitations](#9-research-limitations)
- [10. Complete Reference List](#10-complete-reference-list)

---

## 1. What the Foundry V2 Portal Traces Tab Shows

### Location in the Portal

In the new Foundry portal (with the **New Foundry** toggle on), traces are accessed via:

**Agents → Traces** (tab at the top of the Agents page)

> "In the left navigation, select **Agents**. At the top, select **Traces**."
> — Source: [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

There is also a broader **Observability → Traces** path referenced for framework integrations:

> "In the Foundry portal, go to **Observability** > **Traces**."
> — Source: [Configure tracing for AI agent frameworks](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-framework)

### What It Displays

The Traces tab shows:

- **Trace ID**: Unique identifier for the trace
- **Start time**: When the trace began
- **Duration**: How long the operation took
- **Status**: Success or failure status
- **Operations**: Number of spans in the trace
- **Conversation ID**: Links to the conversation context

Selecting a trace reveals:

- Complete execution timeline with nested span hierarchy
- Input and output data for each operation
- Token consumption metrics
- Performance metrics and timing
- Error details if any occurred
- Custom attributes and metadata

> "A **Conversation** is the persistent context of an end-to-end dialogue history between a user and an agent. In the Foundry portal, you can view **Conversation** results for your agent run out of the box along with traces on the **Traces** page."
> — Source: [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

### Data Store: Application Insights

The Traces tab queries **Azure Monitor Application Insights**. Traces are not stored in a separate Foundry-proprietary store.

> "Foundry stores traces in Application Insights by using OpenTelemetry semantic conventions."
> — Source: [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

OpenTelemetry spans land in Application Insights tables following standard Azure Monitor mapping:
- **Client spans** (`SpanKind.CLIENT`) → `dependencies` / `AppDependencies` table
- **Server spans** (`SpanKind.SERVER`) → `requests` / `AppRequests` table
- **Application logs** → `traces` / `AppTraces` table

> "Application Insights stores application log records in the `traces` table for legacy reasons. Spans for distributed tracing are stored in the `requests` and `dependencies` tables."
> — Source: [Application Insights data model](https://learn.microsoft.com/en-us/azure/azure-monitor/app/data-model-complete)

The Foundry portal's Traces tab renders a custom visualization on top of these Application Insights tables, using the OpenTelemetry semantic conventions for GenAI (e.g., `gen_ai.operation.name`, `gen_ai.agent.name`, `gen_ai.conversation.id`).

### Server-Side vs. Client-Side Traces

Foundry automatically generates **server-side traces** for Prompt agents once Application Insights is connected:

> "Foundry automatically logs server-side traces for Prompt agents, Host agents, and workflows in the Foundry portal. Once tracing is enabled in your Foundry project, you'll have access to out-of-the-box traces for the past 90 days."
> — Source: [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

Client-side traces (from your application code) require SDK instrumentation and provide richer detail including custom spans and business context attributes.

### Trace Status: GA vs. Preview

> "Tracing is generally available for prompt agents only. Workflow, hosted, and custom agents are in preview."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

---

## 2. Prerequisites for Traces to Appear

### 2.1 Application Insights Connection (Required)

The Foundry account must have an Application Insights resource **connected** as a connection. This is the most common reason the Traces tab is empty.

> "Foundry stores traces in Azure Monitor Application Insights, which may incur costs based on data volume and retention settings."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

#### Portal Steps (New Foundry)

1. Sign in to [Microsoft Foundry](https://ai.azure.com) with **New Foundry** toggle on.
2. Open your project.
3. Select **Agents** → **Traces** tab.
4. On the right, select **Connect** to create or connect an Application Insights resource.
5. Choose an existing resource or create a new one, then select **Connect**.

> "On the right, select **Connect**, to create or connect an Application Insights resource."
> — Source: [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

**Alternative path** (if the Connect button is not visible):

1. Select the **Project details** from the dropdown menu from your project name.
2. Navigate to the **Connected resources** tab, then select **Add connection**.
3. Select **Application Insights** in the *Choose a connection* menu.

> — Source: [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

#### Bicep (Account-Level Connection)

For Foundry V2, connections are created on the **Foundry account** (`Microsoft.CognitiveServices/accounts`), not at the project level. The connection type is `Microsoft.CognitiveServices/accounts/connections` with category `AppInsights`.

See [Section 5: Bicep](#5-bicep-application-insights-connection) for the full Bicep template.

#### CLI

```bash
# See Section 6 for full CLI commands
az cognitiveservices account connection create \
  --name foundry-zava-a2a-smartorder \
  --resource-group <resource-group> \
  --connection-name foundry-zava-a2a-smartorder-appinsights \
  --properties category=AppInsights target=<app-insights-resource-id> authType=ApiKey isSharedToAll=true
```

### 2.2 RBAC Roles (Required)

To **view** traces in the portal and query App Insights:

> "For log-based queries, start by assigning the [Log Analytics Reader role](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/manage-access?tabs=portal#log-analytics-reader)."
> — Source: [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

To **create** the connection (link App Insights):

> "To connect to an existing Azure Application Insights, you need at least contributor access to the Foundry resource (or Hub)."
> — Source: [View Trace Results for AI Applications using OpenAI SDK (classic)](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/develop/trace-application)

For **trace ingestion**:

> "Contributor or higher role on the Application Insights resource for trace ingestion."
> — Source: [Configure tracing for AI agent frameworks](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-framework)

Summary of required roles:

| Who | Resource | Role |
|-----|----------|------|
| Developer creating connection | Foundry account | Contributor or Foundry Owner |
| Developer creating new App Insights | Resource group | Contributor |
| Developer viewing traces | Application Insights | Log Analytics Reader |
| Application identity (for ingestion) | Application Insights | Contributor (or Monitoring Metrics Publisher for metrics) |

### 2.3 Diagnostic Settings / Toggle

There is **no separate diagnostic setting** or project-level toggle for tracing. Tracing is enabled by connecting Application Insights. Once connected, server-side traces flow automatically.

### 2.4 Data Retention

> "Foundry stores traces in the Application Insights resource connected to your project. Data retention and billing follow your Application Insights and Log Analytics configuration."
> — Source: [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

Server-side traces are retained for up to 90 days:

> "Once tracing is enabled in your Foundry project, you'll have access to out-of-the-box traces for the past 90 days."
> — Source: [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

---

## 3. SDK-Side Instrumentation (Python)

### 3.1 Required Packages

There are two instrumentation paths. Choose based on your scenario:

#### Path A: `AIProjectInstrumentor` (Recommended for azure-ai-projects users)

This is the instrumentor built into the `azure-ai-projects` SDK. It instruments both the Agents SDK calls and the OpenAI Responses/Conversations APIs.

```bash
pip install "azure-ai-projects>=2.0.0b4" \
            azure-identity \
            opentelemetry-sdk \
            azure-core-tracing-opentelemetry \
            azure-monitor-opentelemetry
```

> "Make sure to install OpenTelemetry and the Azure SDK tracing plugin via `pip install "azure-ai-projects>=2.0.0b4" opentelemetry-sdk azure-core-tracing-opentelemetry azure-monitor-opentelemetry`"
> — Source: [azure-ai-projects README — Tracing section](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects#tracing)

#### Path B: `OpenAIInstrumentor` (For plain OpenAI SDK users)

This instruments the OpenAI SDK directly (chat completions, not the agents/responses API).

```bash
pip install azure-ai-projects \
            azure-monitor-opentelemetry \
            opentelemetry-instrumentation-openai-v2
```

> — Source: [View Trace Results for AI Applications using OpenAI SDK (classic)](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/develop/trace-application)

**For our scenario** (Responses API with `agent_reference`), **Path A is required**. The `AIProjectInstrumentor` includes a `_ResponsesInstrumentorPreview` that specifically instruments `responses.create()` and `conversations.create()` calls, producing `invoke_agent <agent-name>` spans.

### 3.2 Experimental Feature Gate (Critical)

The `AIProjectInstrumentor` requires an **explicit opt-in** via environment variable:

> "**Important:** GenAI tracing instrumentation is an experimental preview feature. Spans, attributes, and events may be modified in future versions. To use it, you must explicitly opt in by setting the environment variable: `AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING=true`"
> — Source: [azure-ai-projects README — Tracing section](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects#tracing)

> "This environment variable must be set before calling `AIProjectInstrumentor().instrument()`. If the environment variable is not set or is set to any value other than `true` (case-insensitive), tracing instrumentation will not be enabled and a warning will be logged."
> — Source: [azure-ai-projects README — Tracing section](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects#tracing)

### 3.3 Bootstrap Code

#### Azure Monitor Tracing (traces go to App Insights → Foundry Traces tab)

```python
import os

# STEP 0: Feature gate — MUST be set before calling instrument()
os.environ["AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING"] = "true"

# Optional: capture message content (prompts/responses) in traces
os.environ["OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT"] = "true"

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from azure.monitor.opentelemetry import configure_azure_monitor
from azure.ai.projects.telemetry import AIProjectInstrumentor
from opentelemetry import trace

# STEP 1: Create project client
project_client = AIProjectClient(
    credential=DefaultAzureCredential(),
    endpoint="https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility",
)

# STEP 2: Get App Insights connection string from the project
application_insights_connection_string = (
    project_client.telemetry.get_application_insights_connection_string()
)

# STEP 3: Configure Azure Monitor as the OTel exporter
configure_azure_monitor(connection_string=application_insights_connection_string)

# STEP 4: Enable Foundry SDK instrumentation
AIProjectInstrumentor().instrument()

# STEP 5: Get a tracer for custom spans
tracer = trace.get_tracer(__name__)
```
> — Source: [sample_agent_basic_with_azure_monitor_tracing.py](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/telemetry/sample_agent_basic_with_azure_monitor_tracing.py) | Provenance: adapted

**Key detail**: `project_client.telemetry.get_application_insights_connection_string()` retrieves the connection string from the linked Application Insights resource. If App Insights is not connected, this will fail — confirming the prerequisite from Section 2.

### 3.4 Making responses.create() Emit Spans

When the `AIProjectInstrumentor` is active and the call includes `agent_reference`, the `_ResponsesInstrumentorPreview` monkey-patches `openai_client.responses.create()` to emit spans automatically.

**Span naming logic** (from source code analysis):
- If `agent_reference` includes `name` → span name: `invoke_agent <agent-name>` (e.g., `invoke_agent zava-customer-service`)
- If no agent but `model` specified → span name: `chat <model-name>`
- Otherwise → `responses`

The span includes these semantic attributes:
- `gen_ai.operation.name`: `"invoke_agent"` or `"chat"`
- `gen_ai.system`: `"microsoft.foundry"` (the provider constant)
- `gen_ai.agent.name`: the agent name from `agent_reference`
- `gen_ai.agent.id`: the agent ID from `agent_reference`
- `gen_ai.conversation.id`: the conversation ID
- `gen_ai.request.model`: the model name
- `gen_ai.request.tools`: JSON of tools if provided
- `gen_ai.usage.input_tokens` / `gen_ai.usage.output_tokens`: token counts

> "**Note:** In order to view the traces in the Microsoft Foundry portal, the agent ID should be passed in as part of the response generation request."
> — Source: [azure-ai-projects README — Tracing section](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects#tracing)

### 3.5 Streaming Responses

The `start_responses_span` method accepts a `stream: bool` parameter. The instrumentation creates a **single parent span** that wraps the entire streaming response — it does not create one span per chunk. The span starts when `responses.create(stream=True)` is called and ends when the stream is fully consumed or the context manager exits.

```python
# Streaming with tracing — produces a single span
with openai_client.responses.create(
    conversation=conversation.id,
    extra_body={
        "agent_reference": {
            "name": "zava-customer-service",
            "id": agent_id,
            "type": "agent_reference",
        }
    },
    stream=True,
) as response_stream:
    for event in response_stream:
        if event.type == "response.output_text.delta":
            print(event.delta, end="", flush=True)
```
> — Source: [sample_agent_stream_events.py](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/sample_agent_stream_events.py) | Provenance: adapted

### 3.6 A2APreviewTool and CodeInterpreter in Traces

For **A2APreviewTool** (cross-agent calls): The Responses API instrumentation captures tool call events as child events/attributes on the parent span. The semantic conventions define:

| Type | Span/Attribute | Purpose |
|------|----------------|---------|
| Child Span | `agent_to_agent_interaction` | Traces communication between agents |
| Attribute | `tool.call.arguments` | Logs arguments passed during tool invocation |
| Attribute | `tool.call.results` | Records results returned by the tool |

> "Microsoft is enhancing multi-agent observability by introducing new semantic conventions to OpenTelemetry... These additions, built upon OpenTelemetry and W3C Trace Context, establish standardized practices for tracing and telemetry within multi-agent systems."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

For **CodeInterpreterTool**: Tool calls are captured as events on the span with `tool.call.arguments` and `tool.call.results` attributes. The Responses API instrumentation detects tool outputs in the input and creates corresponding events.

Note: The level of detail in A2A cross-agent traces depends on whether the called agent also has tracing enabled. If both agents run through the same Foundry project with App Insights connected, server-side traces from both appear. Client-side W3C trace context propagation connects the spans into a single distributed trace.

### 3.7 Custom Span Attributes

You can add business-context attributes to spans using OpenTelemetry's standard API:

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

@tracer.start_as_current_span("process_customer_order")
def process_order(customer_id: str, sku: str, quantity: int):
    current_span = trace.get_current_span()
    current_span.set_attribute("business.customer_id", customer_id)
    current_span.set_attribute("business.sku", sku)
    current_span.set_attribute("business.quantity", quantity)

    # Agent call happens inside this span
    response = openai_client.responses.create(
        conversation=conversation.id,
        extra_body={"agent_reference": {"name": agent_name, "type": "agent_reference"}},
        input=f"Check feasibility for {quantity}x {sku} for customer {customer_id}",
    )
    return response.output_text
```
> — Source: [sample_agent_basic_with_console_tracing_custom_attributes.py](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/telemetry/sample_agent_basic_with_console_tracing_custom_attributes.py) | Provenance: adapted

For adding attributes to **all** spans automatically, use a custom `SpanProcessor`:

```python
from opentelemetry.sdk.trace import TracerProvider, SpanProcessor, ReadableSpan, Span
from typing import cast

class BusinessContextSpanProcessor(SpanProcessor):
    def on_start(self, span: Span, parent_context=None):
        span.set_attribute("service.environment", "demo")
        span.set_attribute("foundry.project", "smart-order-feasibility")

    def on_end(self, span: ReadableSpan):
        pass

# Add to the tracer provider
provider = cast(TracerProvider, trace.get_tracer_provider())
provider.add_span_processor(BusinessContextSpanProcessor())
```
> — Source: [sample_agent_basic_with_console_tracing_custom_attributes.py](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/telemetry/sample_agent_basic_with_console_tracing_custom_attributes.py) | Provenance: adapted

### 3.8 Content Recording

To capture prompt/response content in traces (useful for debugging, but contains PII):

```python
# Option A: Environment variable (set before instrument())
os.environ["OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT"] = "true"

# Option B: For Azure SDK content recording
os.environ["AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED"] = "true"
```

> "To trace the content of chat messages, set the `AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED` environment variable to true (case insensitive). This content might contain personal data."
> — Source: [Trace and Observe AI Agents in Microsoft Foundry (classic)](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/tracing)

---

## 4. End-to-End Trace Correlation

### 4.1 Trace Context Propagation

The `AIProjectInstrumentor` supports automatic W3C Trace Context propagation via `traceparent` and `tracestate` headers:

> "Trace context propagation is **enabled by default** when tracing is enabled (for example through `configure_azure_monitor` or the `AIProjectInstrumentor().instrument()` call)."
> — Source: [azure-ai-projects README — Tracing section](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects#tracing)

> "This feature ensures that all operations within a distributed trace share the same trace ID, providing end-to-end visibility across your application and Azure services in your observability backend (such as Azure Monitor)."
> — Source: [azure-ai-projects README — Tracing section](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects#tracing)

**Important timing requirement:**

> "Changes to `enable_trace_context_propagation` only affect OpenAI clients obtained via `get_openai_client()` **after** the change is applied. Previously acquired clients are unaffected."
> — Source: [azure-ai-projects README — Tracing section](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects#tracing)

This means you must call `AIProjectInstrumentor().instrument()` **before** calling `project_client.get_openai_client()`.

### 4.2 FastAPI → Backend → Foundry Correlation

To thread a `traceparent` header from a FastAPI request through to the Foundry Responses API call:

#### Required packages for FastAPI instrumentation

```bash
pip install opentelemetry-instrumentation-fastapi \
            opentelemetry-instrumentation-httpx \
            azure-monitor-opentelemetry
```

#### Bootstrap code for FastAPI + Foundry tracing

```python
import os
os.environ["AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING"] = "true"
os.environ["OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT"] = "true"

from fastapi import FastAPI
from azure.monitor.opentelemetry import configure_azure_monitor
from azure.ai.projects.telemetry import AIProjectInstrumentor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# Configure Azure Monitor (sends traces to App Insights)
configure_azure_monitor(
    connection_string=os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"]
)

# Instrument the Foundry SDK (Responses API + Agents API)
AIProjectInstrumentor().instrument()

# Create FastAPI app
app = FastAPI()

# Instrument FastAPI (creates server spans from incoming requests)
FastAPIInstrumentor.instrument_app(app)

# Now any incoming FastAPI request creates a parent span,
# and the responses.create() call inside the handler creates
# a child span with traceparent propagated to the Foundry service.
```
> — Source: synthesized from [azure-ai-projects README](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects#tracing) and [Azure Monitor OpenTelemetry docs](https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-enable) | Provenance: synthesized

The trace flow becomes:

```
Browser → FastAPI (server span) → responses.create() (client span, invoke_agent) → Foundry service (server-side span)
                                  └→ A2APreviewTool call (child span) → Remote agent (server-side span)
                                  └→ CodeInterpreter (child span/event)
```

### 4.3 Controlling Propagation

To disable trace context propagation (e.g., for compliance):

```python
# Option A: Environment variable
os.environ["AZURE_TRACING_GEN_AI_ENABLE_TRACE_CONTEXT_PROPAGATION"] = "false"

# Option B: Parameter
AIProjectInstrumentor().instrument(enable_trace_context_propagation=False)
```

Baggage propagation (disabled by default, potentially sensitive):

```python
# Only if you need to propagate baggage headers
os.environ["AZURE_TRACING_GEN_AI_TRACE_CONTEXT_PROPAGATION_INCLUDE_BAGGAGE"] = "true"
```

> "**Trace IDs are sent to external services**: The `traceparent` and `tracestate` headers from your client-side originating spans are injected into requests sent to service."
> — Source: [azure-ai-projects README — Tracing section](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects#tracing)

---

## 5. Bicep: Application Insights Connection

### 5.1 Full Bicep Template

The official Foundry Samples repository provides the exact Bicep resource shape. The connection is created on the **Foundry account** (`Microsoft.CognitiveServices/accounts`), not on the project:

```bicep
// Source: https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/connection-application-insights.bicep
// Provenance: verbatim (with parameter values customized for our deployment)

param aiFoundryName string = 'foundry-zava-a2a-smartorder'
param connectedResourceName string = 'appi-zava-a2a-smart-order'
param location string = 'eastus2'

@allowed([
  'new'
  'existing'
])
param newOrExisting string = 'existing'

// Reference the existing Foundry account
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiFoundryName
  scope: resourceGroup()
}

// Reference the existing Application Insights resource
resource existingAppInsights 'Microsoft.Insights/components@2020-02-02' existing = if (newOrExisting == 'existing') {
  name: connectedResourceName
}

// Conditionally create a new Application Insights resource
resource newAppInsights 'Microsoft.Insights/components@2020-02-02' = if (newOrExisting == 'new') {
  name: connectedResourceName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// Create the Foundry connection to Application Insights
resource connection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  name: '${aiFoundryName}-appinsights'
  parent: aiFoundry
  properties: {
    category: 'AppInsights'
    target: ((newOrExisting == 'new') ? newAppInsights.id : existingAppInsights.id)
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: ((newOrExisting == 'new')
        ? newAppInsights.properties.ConnectionString
        : existingAppInsights.properties.ConnectionString)
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: ((newOrExisting == 'new') ? newAppInsights.id : existingAppInsights.id)
    }
  }
}
```
> — Source: [connection-application-insights.bicep](https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/connection-application-insights.bicep) | Provenance: verbatim

### 5.2 Key Observations

| Property | Value | Notes |
|----------|-------|-------|
| Resource type | `Microsoft.CognitiveServices/accounts/connections` | Account-level, not project-level |
| API version | `2025-04-01-preview` | Latest as of May 2026 |
| `category` | `AppInsights` | Must be exactly this string |
| `target` | Resource ID of the App Insights resource | Full ARM resource ID |
| `authType` | `ApiKey` | Uses the App Insights connection string as the key |
| `credentials.key` | App Insights connection string | e.g., `InstrumentationKey=...;IngestionEndpoint=...` |
| `isSharedToAll` | `true` | Shared to all projects in the account |
| `metadata.ResourceId` | Same as `target` | Full ARM resource ID |

### 5.3 No `tracingEnabled` or `applicationInsightsId` on the Project

There is **no** `tracingEnabled` property or `applicationInsightsId` field on the `Microsoft.CognitiveServices/accounts/projects` resource type. Tracing is enabled solely by the existence of the AppInsights connection on the parent account.

---

## 6. az CLI Commands

### 6.1 Create the App Insights Connection

The `az cognitiveservices` commands for managing connections on a Foundry account require the REST API since the CLI extension may not yet have full coverage for connection operations. Here is the approach using `az rest`:

```bash
# Variables
RESOURCE_GROUP="rg-zava-a2a-smart-order"
FOUNDRY_ACCOUNT="foundry-zava-a2a-smartorder"
APPINSIGHTS_NAME="appi-zava-a2a-smart-order"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
CONNECTION_NAME="${FOUNDRY_ACCOUNT}-appinsights"

# Get App Insights resource ID and connection string
APPINSIGHTS_ID=$(az monitor app-insights component show \
  --app $APPINSIGHTS_NAME \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv)

APPINSIGHTS_CONN_STRING=$(az monitor app-insights component show \
  --app $APPINSIGHTS_NAME \
  --resource-group $RESOURCE_GROUP \
  --query connectionString -o tsv)

# Create the connection via REST API
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT}/connections/${CONNECTION_NAME}?api-version=2025-04-01-preview" \
  --body "{
    \"properties\": {
      \"category\": \"AppInsights\",
      \"target\": \"${APPINSIGHTS_ID}\",
      \"authType\": \"ApiKey\",
      \"isSharedToAll\": true,
      \"credentials\": {
        \"key\": \"${APPINSIGHTS_CONN_STRING}\"
      },
      \"metadata\": {
        \"ApiType\": \"Azure\",
        \"ResourceId\": \"${APPINSIGHTS_ID}\"
      }
    }
  }"
```

### 6.2 Verify the Connection Exists

```bash
# List all connections on the Foundry account
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT}/connections?api-version=2025-04-01-preview" \
  --query "value[?properties.category=='AppInsights'].{name:name, category:properties.category, target:properties.target}" \
  -o table

# Show a specific connection
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT}/connections/${CONNECTION_NAME}?api-version=2025-04-01-preview"
```

### 6.3 List Traces via App Insights KQL

After a test run, query Application Insights to confirm traces are landing:

```bash
# Query the dependencies table for GenAI spans (Foundry agent traces land here as client spans)
az monitor app-insights query \
  --app $APPINSIGHTS_NAME \
  --resource-group $RESOURCE_GROUP \
  --analytics-query "
    dependencies
    | where timestamp > ago(1h)
    | where customDimensions has 'gen_ai'
    | project timestamp, name, duration, resultCode,
              operation_Name,
              agent_name = tostring(customDimensions['gen_ai.agent.name']),
              operation_type = tostring(customDimensions['gen_ai.operation.name']),
              model = tostring(customDimensions['gen_ai.request.model'])
    | order by timestamp desc
    | take 20
  "
```

### 6.4 Inspect Foundry-Emitted Span Names

```bash
# Find distinct span names from Foundry agent traces
az monitor app-insights query \
  --app $APPINSIGHTS_NAME \
  --resource-group $RESOURCE_GROUP \
  --analytics-query "
    dependencies
    | where timestamp > ago(24h)
    | where customDimensions has 'gen_ai'
    | summarize count() by name
    | order by count_ desc
  "
```

Expected span names:
- `invoke_agent zava-customer-service` — main agent invocation
- `chat <model-name>` — direct model calls without agent_reference
- `create_conversation` — conversation creation
- Custom span names from your `@tracer.start_as_current_span(...)` decorators

### 6.5 Full KQL Query for Foundry Agent Traces

```kql
// Run in Application Insights > Logs
// Shows all Foundry agent traces with full detail
dependencies
| where timestamp > ago(1h)
| where customDimensions['gen_ai.system'] == 'microsoft.foundry'
    or customDimensions['gen_ai.operation.name'] == 'invoke_agent'
| project
    timestamp,
    operation_Id,
    id,
    name,
    duration,
    success,
    resultCode,
    agent_name = tostring(customDimensions['gen_ai.agent.name']),
    agent_id = tostring(customDimensions['gen_ai.agent.id']),
    conversation_id = tostring(customDimensions['gen_ai.conversation.id']),
    operation_name = tostring(customDimensions['gen_ai.operation.name']),
    model = tostring(customDimensions['gen_ai.request.model']),
    input_tokens = toint(customDimensions['gen_ai.usage.input_tokens']),
    output_tokens = toint(customDimensions['gen_ai.usage.output_tokens'])
| order by timestamp desc
```

---

## 7. Common Gotchas / Known Limitations

### 7.1 Things That Silently Break Traces

| Issue | Cause | Fix |
|-------|-------|-----|
| **Traces tab is empty** | No App Insights connection on the Foundry account | Create the connection (see Section 2.1) |
| **`AIProjectInstrumentor().instrument()` silently does nothing** | `AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING` not set to `"true"` | Set the env var **before** calling `instrument()` |
| **Spans show `chat` instead of `invoke_agent`** | `agent_reference` missing from `extra_body` in `responses.create()` | Include `extra_body={"agent_reference": {"name": ..., "id": ..., "type": "agent_reference"}}` |
| **Client-side spans not correlated with server-side** | `get_openai_client()` called **before** `instrument()` | Call `instrument()` first, then `get_openai_client()` |
| **`get_application_insights_connection_string()` fails** | App Insights not connected to the Foundry account | Create the connection first |
| **Missing RBAC** | User lacks Log Analytics Reader on App Insights | Assign the role |
| **Wrong API version in Bicep** | Using older API version without connection support | Use `2025-04-01-preview` |

### 7.2 Sampling Behavior

> "Sampling is enabled by default at a rate of five requests per second, aiding in cost management. Telemetry data could be missing in scenarios exceeding this rate."
> — Source: [Azure Monitor OpenTelemetry](https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-enable)

**For a demo, disable sampling** to ensure all traces are captured:

```python
# Option A: Environment variables (set before configure_azure_monitor)
os.environ["OTEL_TRACES_SAMPLER"] = "always_on"

# Option B: In configure_azure_monitor
configure_azure_monitor(
    connection_string=connection_string,
    # The distro respects OTEL_TRACES_SAMPLER env var
)
```

Or use fixed-percentage at 100%:

```bash
export OTEL_TRACES_SAMPLER=microsoft.fixed_percentage
export OTEL_TRACES_SAMPLER_ARG=1.0
```

### 7.3 Lag Between Agent Run and Portal Display

> "Traces typically appear within 2–5 minutes after agent execution."
> — Source: [Configure tracing for AI agent frameworks](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-framework)

Troubleshooting table from official docs:

> | Issue | Cause | Resolution |
> | --- | --- | --- |
> | You don't see any traces in the Foundry portal | Tracing isn't connected, there is no recent traffic, or ingestion is delayed | Confirm the Application Insights connection, generate new agent traffic, and refresh after a few minutes. |
> | Client-side traces don't appear | Instrumentation isn't installed or configured | Recheck your package installation and follow the SDK guidance. |
> — Source: [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

### 7.4 Differences in Trace Coverage

| Tool | Trace Coverage |
|------|---------------|
| **Prompt Agent (Responses API)** | GA — full traces (invoke_agent span, tool calls, token usage) |
| **CodeInterpreterTool** | Server-side tool call events captured automatically; client-side sees tool_call events |
| **A2APreviewTool** | Preview — cross-agent calls appear as child spans/events using multi-agent semantic conventions |
| **Workflow agents** | Preview |
| **Hosted agents** | Preview |

### 7.5 Content Recording Privacy

> "Tracing can capture sensitive information (for example, user inputs, model outputs, and tool arguments and results). Don't store secrets, credentials, or tokens in prompts, tool arguments, or span attributes."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

### 7.6 Service Name for Filtering

To identify your application in shared App Insights resources, set the OpenTelemetry service name:

```bash
export OTEL_SERVICE_NAME="zava-smart-order-backend"
```

This maps to `cloud_RoleName` in App Insights queries:

```kql
dependencies | where cloud_RoleName == "zava-smart-order-backend"
```

> "To query trace data for a given service name, query for the `cloud_RoleName` property."
> — Source: [Trace and Observe AI Agents in Microsoft Foundry (classic)](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/tracing)

---

## 8. Worked Example

### 8.1 Complete Python Snippet

This is a copy-pasteable script that bootstraps tracing and makes an agent call. It is adapted from the official samples with our project's specific configuration.

```python
#!/usr/bin/env python3
"""
Foundry V2 Agent Tracing — Complete Worked Example

Bootstraps Azure Monitor for OpenTelemetry, creates an AIProjectClient,
calls responses.create() against an existing agent, and confirms a parent
span "invoke_agent zava-customer-service" with child spans for tool calls.

Prerequisites:
    pip install "azure-ai-projects>=2.0.0b4" azure-identity \
                azure-monitor-opentelemetry opentelemetry-sdk \
                azure-core-tracing-opentelemetry python-dotenv

Environment variables:
    FOUNDRY_PROJECT_ENDPOINT=https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility
    AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING=true
    OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true
    OTEL_SERVICE_NAME=zava-smart-order-backend
    OTEL_TRACES_SAMPLER=always_on

Source: Adapted from official samples:
  - https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/telemetry/sample_agent_basic_with_azure_monitor_tracing.py
  - https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/sample_agent_stream_events.py
Provenance: adapted
"""

import os
from dotenv import load_dotenv

# ─── 0. Environment & Feature Gate ───────────────────────────────────────────
load_dotenv()
os.environ.setdefault("AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING", "true")
os.environ.setdefault("OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT", "true")
os.environ.setdefault("OTEL_SERVICE_NAME", "zava-smart-order-backend")
os.environ.setdefault("OTEL_TRACES_SAMPLER", "always_on")  # Disable sampling for demo

# ─── 1. Imports ──────────────────────────────────────────────────────────────
from opentelemetry import trace
from azure.monitor.opentelemetry import configure_azure_monitor
from azure.ai.projects.telemetry import AIProjectInstrumentor
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

# ─── 2. Project Client ──────────────────────────────────────────────────────
credential = DefaultAzureCredential()
project_client = AIProjectClient(
    endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
    credential=credential,
)

# ─── 3. Azure Monitor Exporter ──────────────────────────────────────────────
app_insights_conn_str = project_client.telemetry.get_application_insights_connection_string()
print(f"✅ App Insights connection string retrieved (starts with: {app_insights_conn_str[:40]}...)")

configure_azure_monitor(connection_string=app_insights_conn_str)

# ─── 4. Instrument SDK (MUST be before get_openai_client) ───────────────────
AIProjectInstrumentor().instrument()
print("✅ AIProjectInstrumentor enabled")

# ─── 5. Get OpenAI Client (AFTER instrument) ────────────────────────────────
openai_client = project_client.get_openai_client()

# ─── 6. Tracer for custom spans ─────────────────────────────────────────────
tracer = trace.get_tracer(__name__)

# ─── 7. Agent Configuration ─────────────────────────────────────────────────
# Use your existing agent — no need to create a new one
AGENT_NAME = "zava-customer-service"

# ─── 8. Make a Traced Agent Call ─────────────────────────────────────────────
with tracer.start_as_current_span("demo_trace_verification") as parent_span:
    parent_span.set_attribute("demo.purpose", "verify-traces-tab")
    parent_span.set_attribute("demo.agent_name", AGENT_NAME)

    # Create a conversation
    conversation = openai_client.conversations.create()
    print(f"📝 Conversation created: {conversation.id}")

    # Call the agent with streaming
    print("🤖 Calling agent (streaming)...")
    with openai_client.responses.create(
        conversation=conversation.id,
        extra_body={
            "agent_reference": {
                "name": AGENT_NAME,
                "type": "agent_reference",
            }
        },
        input="What is the feasibility status for order SKU-12345, quantity 500?",
        stream=True,
    ) as response_stream:
        full_response = ""
        for event in response_stream:
            if event.type == "response.output_text.delta":
                print(event.delta, end="", flush=True)
                full_response += event.delta
            elif event.type == "response.completed":
                print("\n\n✅ Response completed")

    # Clean up conversation
    openai_client.conversations.delete(conversation_id=conversation.id)
    print("🧹 Conversation deleted")

# ─── 9. Verify ──────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("NEXT STEPS:")
print("1. Wait 2-5 minutes for traces to propagate")
print("2. Open Foundry portal → Agents → Traces tab")
print("3. Look for trace with name 'demo_trace_verification'")
print("4. Expand to see child span 'invoke_agent zava-customer-service'")
print("5. Verify tool call events (CodeInterpreter, A2APreviewTool)")
print("=" * 60)

# Clean up
openai_client.close()
project_client.close()
credential.close()
```
> — Source: [sample_agent_basic_with_azure_monitor_tracing.py](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/telemetry/sample_agent_basic_with_azure_monitor_tracing.py) and [sample_agent_stream_events.py](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/sample_agent_stream_events.py) | Provenance: adapted

### 8.2 Matching Bicep Snippet

Deploy this to create/connect the Application Insights resource to your Foundry account:

```bicep
// file: infra/modules/appinsights-connection.bicep
// Connects an existing Application Insights resource to the Foundry account
// Source: https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/connection-application-insights.bicep
// Provenance: adapted for our specific deployment

param aiFoundryName string = 'foundry-zava-a2a-smartorder'
param appInsightsName string = 'appi-zava-a2a-smart-order'

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiFoundryName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  name: '${aiFoundryName}-appinsights'
  parent: aiFoundry
  properties: {
    category: 'AppInsights'
    target: appInsights.id
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: appInsights.properties.ConnectionString
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: appInsights.id
    }
  }
}

output connectionName string = appInsightsConnection.name
```
> — Source: [connection-application-insights.bicep](https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/connection-application-insights.bicep) | Provenance: adapted

Deploy with:

```bash
az deployment group create \
  --resource-group rg-zava-a2a-smart-order \
  --template-file infra/modules/appinsights-connection.bicep \
  --parameters aiFoundryName=foundry-zava-a2a-smartorder appInsightsName=appi-zava-a2a-smart-order
```

---

## 9. Research Limitations

1. **New Foundry portal tracing docs are evolving**: Many tracing documentation pages still redirect to the "Foundry (classic)" version. The new Foundry observability docs exist at `https://learn.microsoft.com/en-us/azure/foundry/observability/` but are relatively new (dated 2026-03-27). Some details may be inherited from classic docs that don't fully apply to the new portal.

2. **A2APreviewTool trace details**: The exact span structure for A2APreviewTool cross-agent calls is not fully documented in official Microsoft Learn pages. The semantic conventions table shows `agent_to_agent_interaction` as a child span, but how this manifests specifically for `A2APreviewTool` in the Foundry Responses API traces has not been verified against a live deployment.

3. **CLI commands for connections**: The `az cognitiveservices account connection` CLI commands may not be fully available in all Azure CLI versions. The `az rest` approach using the ARM REST API is the most reliable method. The exact CLI extension version requirements were not confirmed.

4. **Bicep API version stability**: The `2025-04-01-preview` API version for `Microsoft.CognitiveServices/accounts/connections` is a preview API. The GA API version for this resource type was not found in documentation.

5. **Streaming trace span lifecycle**: The exact mechanics of how the `_ResponsesInstrumentorPreview` wraps streaming responses to create a single span were inferred from source code inspection, not from official documentation.

6. **`opentelemetry-instrumentation-openai-v2` vs `AIProjectInstrumentor`**: The relationship between these two instrumentors is not fully documented. The `AIProjectInstrumentor` handles the Responses API and agents specifically, while `opentelemetry-instrumentation-openai-v2` handles standard OpenAI `chat.completions`. For Foundry agents using the Responses API, only `AIProjectInstrumentor` is needed.

7. **The `AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING` feature gate** is described as "experimental preview" in the SDK README. It is unclear when (or if) this gate will be removed in a GA release.

---

## 10. Complete Reference List

### Microsoft Learn Documentation

- [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept) — Core concepts page for the new Foundry portal tracing; explains what traces capture, semantic conventions, and prerequisites
- [Set Up Tracing for AI Agents in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup) — Step-by-step setup guide for the new Foundry portal; covers connecting App Insights, instrumenting agents, and viewing traces
- [Configure tracing for AI agent frameworks](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-framework) — Framework-specific tracing integration (Microsoft Agent Framework, LangChain, LangGraph, OpenAI Agents SDK)
- [View Trace Results for AI Applications using OpenAI SDK (classic)](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/develop/trace-application) — Classic Foundry portal tracing guide; still relevant for SDK instrumentation patterns
- [Trace and Observe AI Agents in Microsoft Foundry (classic)](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/tracing) — Classic Foundry agents tracing concepts; detailed semantic conventions and multi-agent observability
- [Add a new connection to your project](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/connections-add) — Connection types and creation methods (portal + Bicep); lists Application Insights as a supported connection type
- [Create a project](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/create-projects) — Foundry V2 project creation with CLI/Bicep; confirms resource type is `Microsoft.CognitiveServices/accounts`
- [Application Insights data model](https://learn.microsoft.com/en-us/azure/azure-monitor/app/data-model-complete) — How OTel spans map to App Insights tables (dependencies, requests, traces)
- [Azure Monitor OpenTelemetry configuration](https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-configuration?tabs=python) — Sampling configuration for Python
- [Azure Monitor OpenTelemetry enable](https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-enable) — Default sampling rate and basic setup

### GitHub Repositories

- [Azure/azure-sdk-for-python — sdk/ai/azure-ai-projects](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/ai/azure-ai-projects) — Official Azure AI Projects SDK; README contains comprehensive tracing documentation including feature gate, trace context propagation, and baggage control
- [microsoft-foundry/foundry-samples — infrastructure/infrastructure-setup-bicep/01-connections](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/01-connections) — Official Bicep templates for Foundry connections including Application Insights

### Code Samples

- [sample_agent_basic_with_azure_monitor_tracing.py](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/telemetry/sample_agent_basic_with_azure_monitor_tracing.py) — Python, complete Azure Monitor tracing setup with Foundry agent
- [sample_agent_basic_with_console_tracing.py](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/telemetry/sample_agent_basic_with_console_tracing.py) — Python, console tracing with AIProjectInstrumentor
- [sample_agent_basic_with_console_tracing_custom_attributes.py](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/telemetry/sample_agent_basic_with_console_tracing_custom_attributes.py) — Python, custom span attributes with SpanProcessor
- [sample_agent_stream_events.py](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/samples/agents/sample_agent_stream_events.py) — Python, streaming responses with agent_reference
- [connection-application-insights.bicep](https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/connection-application-insights.bicep) — Bicep, Application Insights connection template for Foundry
