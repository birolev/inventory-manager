export interface FallbackModel {
  provider: string;
  id: string;
  envKey: string;
}

export class ProviderError extends Error {
  constructor(
    message: string,
    readonly provider: string,
    readonly model: string,
    readonly status: number | null,
    readonly retryable: boolean,
  ) {
    super(message);
  }
}

export function isRetryableStatus(status: number): boolean {
  return status === 408 || status === 409 || status === 425 || status === 429 || status >= 500;
}

export type FallbackEvent =
  | { type: "missing-key" | "cooling-down"; model: string; detail: string }
  | { type: "retry"; model: string; attempt: number; delayMs: number; detail: string }
  | { type: "failure"; model: string; attempt: number; status: number | null; detail: string }
  | { type: "cooldown"; model: string; cooldownMs: number }
  | { type: "success"; model: string; attempt: number };

export type FallbackOutcome<T> =
  | { ok: true; result: T; model: string }
  | { ok: false; error: string; attempted: string[]; coolingDown: string[] };

export interface FallbackOptions<T> {
  models: readonly FallbackModel[];
  attemptsPerModel?: number;
  retryBaseDelayMs?: number;
  retryMaxDelayMs?: number;
  random?: () => number;
  getApiKey: (model: FallbackModel) => string | undefined;
  isAvailable: (model: FallbackModel) => Promise<boolean>;
  callModel: (model: FallbackModel, apiKey: string) => Promise<T>;
  recordSuccess: (model: FallbackModel) => Promise<void>;
  recordFailure: (model: FallbackModel) => Promise<number>;
  wait: (ms: number) => Promise<void>;
  onEvent?: (event: FallbackEvent) => void;
}

export async function runModelFallback<T>(
  options: FallbackOptions<T>,
): Promise<FallbackOutcome<T>> {
  const attemptsPerModel = options.attemptsPerModel ?? 3;
  const retryBaseDelayMs = options.retryBaseDelayMs ?? 500;
  const retryMaxDelayMs = options.retryMaxDelayMs ?? 4_000;
  const random = options.random ?? Math.random;
  const attempted: string[] = [];
  const unavailable: string[] = [];

  for (const model of options.models) {
    const apiKey = options.getApiKey(model);
    if (!apiKey) {
      unavailable.push(model.id);
      options.onEvent?.({
        type: "missing-key",
        model: model.id,
        detail: `${model.envKey} is not configured`,
      });
      continue;
    }

    if (!await options.isAvailable(model)) {
      unavailable.push(model.id);
      options.onEvent?.({
        type: "cooling-down",
        model: model.id,
        detail: "Circuit is cooling down",
      });
      continue;
    }

    attempted.push(model.id);
    for (let attempt = 1; attempt <= attemptsPerModel; attempt++) {
      try {
        const result = await options.callModel(model, apiKey);
        await options.recordSuccess(model);
        options.onEvent?.({ type: "success", model: model.id, attempt });
        return { ok: true, result, model: model.id };
      } catch (error) {
        const providerError = error instanceof ProviderError
          ? error
          : new ProviderError(String(error), model.provider, model.id, null, true);
        options.onEvent?.({
          type: "failure",
          model: model.id,
          attempt,
          status: providerError.status,
          detail: providerError.message,
        });

        if (providerError.retryable && attempt < attemptsPerModel) {
          const exponentialDelay = Math.min(
            retryMaxDelayMs,
            retryBaseDelayMs * 2 ** (attempt - 1),
          );
          const delayMs = Math.round(exponentialDelay * (0.8 + random() * 0.4));
          options.onEvent?.({
            type: "retry",
            model: model.id,
            attempt,
            delayMs,
            detail: providerError.message,
          });
          await options.wait(delayMs);
          continue;
        }

        const cooldownMs = await options.recordFailure(model);
        options.onEvent?.({ type: "cooldown", model: model.id, cooldownMs });
        break;
      }
    }
  }

  return {
    ok: false,
    error: "All image analysis models are unavailable. Please try again shortly.",
    attempted,
    coolingDown: unavailable,
  };
}
