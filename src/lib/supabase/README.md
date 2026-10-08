# Tipos gerados

Depois de ligar o Supabase CLI ao projeto, gere `database.types.ts` com:

```bash
supabase gen types typescript --linked > src/lib/supabase/database.types.ts
```

O conteúdo gerado deve refletir o schema remoto; nenhum tipo manual foi inventado.
