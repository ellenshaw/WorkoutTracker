/**
 * Tiny in-memory sliding-window limiter. Good enough for one server instance; if you run several
 * instances, move this to Redis (or put a gateway with rate limiting in front).
 */
export class RateLimiter {
  private hits = new Map<string, number[]>();

  constructor(private now: () => number = () => Date.now()) {}

  /** Records a hit and returns 0 if allowed, or the seconds to wait if the limit is reached. */
  check(key: string, limit: number, windowMs: number): number {
    const t = this.now();
    const recent = (this.hits.get(key) ?? []).filter((time) => t - time < windowMs);
    if (recent.length >= limit) {
      this.hits.set(key, recent);
      const oldest = recent[0]!;
      return Math.max(1, Math.ceil((oldest + windowMs - t) / 1000));
    }
    recent.push(t);
    this.hits.set(key, recent);
    return 0;
  }

  /** Drops keys with no recent activity so memory doesn't grow forever. */
  sweep(windowMs: number): void {
    const t = this.now();
    for (const [key, times] of this.hits) {
      if (times.every((time) => t - time >= windowMs)) this.hits.delete(key);
    }
  }
}
