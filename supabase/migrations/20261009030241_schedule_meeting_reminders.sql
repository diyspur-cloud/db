-- Cron do SDD: reminders-every-hour (0 * * * *).
--
-- Este arquivo é operacional e não é migration nem parte do reset local.
-- Execute somente em uma sessão administrativa do projeto, depois de publicar
-- scheduled-reminders e registrar no Vault o secret cujo nome é
-- scheduled_reminders_secret. O valor do secret nunca fica neste arquivo.
-- A decisão de público do handler é deliberada: somente reuniões `scheduled`
-- na janela de 48h e RSVP `attending=true`; o SDD não define comportamento
-- para reuniões canceladas/em andamento ou RSVP negativo.

create extension if not exists pg_cron;
create extension if not exists pg_net;

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM vault.decrypted_secrets
    WHERE name = 'scheduled_reminders_secret'
  ) THEN
    RAISE EXCEPTION
      'Vault secret scheduled_reminders_secret is required before scheduling';
  END IF;

  SELECT jobid
    INTO v_job_id
    FROM cron.job
   WHERE jobname = 'reminders-every-hour';

  -- Não criar uma segunda execução com o mesmo nome. Se o job já existir,
  -- conferir cron.job e a assinatura de cron.alter_job na versão instalada
  -- antes de qualquer ajuste operacional.
  IF v_job_id IS NULL THEN
    PERFORM cron.schedule(
      'reminders-every-hour',
      '0 * * * *',
      $job$
        SELECT net.http_post(
          url := 'https://xjhehhfhhoomblcggjpk.supabase.co/functions/v1/scheduled-reminders',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-scheduled-reminders-secret',
            (SELECT decrypted_secret
               FROM vault.decrypted_secrets
              WHERE name = 'scheduled_reminders_secret')
          ),
          body := '{}'::jsonb
        ) AS request_id;
      $job$
    );
  END IF;
END
$$;
