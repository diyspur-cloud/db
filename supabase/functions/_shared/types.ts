export type ApiFailure = {
  error: string;
  attempt_id?: string;
  retry_after_seconds?: number;
};

export type ApiResult<T> = T | ApiFailure;
