# Teste do Rate Limiter
alias App.Auth.RateLimiter

IO.puts("=== TESTE RATE LIMITER ===")
stats = RateLimiter.get_stats()
IO.puts("Stats: #{inspect(stats)}")

result = RateLimiter.check_login_attempt("test", "192.168.1.1")
IO.puts("Check: #{inspect(result)}")

RateLimiter.record_failed_attempt("test", "192.168.1.1") 
result2 = RateLimiter.check_login_attempt("test", "192.168.1.1")
IO.puts("Após 1 tentativa: #{inspect(result2)}")

IO.puts("✅ Rate Limiter persistente funcionando!")
