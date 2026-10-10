-- A41: items_count é mantido pelo banco, nunca pelo frontend.
UPDATE public.reading_lists AS l
   SET items_count = counts.item_count,
       updated_at = GREATEST(l.updated_at, statement_timestamp())
  FROM (
    SELECT l2.id, count(i.id)::integer AS item_count
      FROM public.reading_lists l2
      LEFT JOIN public.reading_list_items i ON i.list_id = l2.id
     GROUP BY l2.id
  ) AS counts
 WHERE l.id = counts.id;

CREATE OR REPLACE FUNCTION private.sync_reading_list_item_count()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_list uuid;
BEGIN
  v_list := CASE WHEN TG_OP = 'DELETE' THEN OLD.list_id ELSE NEW.list_id END;
  UPDATE public.reading_lists
     SET items_count = (SELECT count(*)::integer FROM public.reading_list_items WHERE list_id = v_list),
         updated_at = statement_timestamp()
   WHERE id = v_list;
  IF TG_OP = 'UPDATE' AND OLD.list_id IS DISTINCT FROM NEW.list_id THEN
    UPDATE public.reading_lists
       SET items_count = (SELECT count(*)::integer FROM public.reading_list_items WHERE list_id = OLD.list_id),
           updated_at = statement_timestamp()
     WHERE id = OLD.list_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_reading_list_item_count ON public.reading_list_items;
CREATE TRIGGER trg_sync_reading_list_item_count
  AFTER INSERT OR UPDATE OR DELETE ON public.reading_list_items
  FOR EACH ROW EXECUTE FUNCTION private.sync_reading_list_item_count();
REVOKE ALL ON FUNCTION private.sync_reading_list_item_count() FROM PUBLIC, anon, authenticated;
