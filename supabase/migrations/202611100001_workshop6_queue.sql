ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS location_accuracy_m DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS location_captured_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_latitude'
  ) THEN
    ALTER TABLE public.clients ADD CONSTRAINT valid_latitude
      CHECK (lat IS NULL OR lat BETWEEN -90 AND 90);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_longitude'
  ) THEN
    ALTER TABLE public.clients ADD CONSTRAINT valid_longitude
      CHECK (lng IS NULL OR lng BETWEEN -180 AND 180);
  END IF;
END $$;

CREATE OR REPLACE VIEW public.queue_clients AS
  SELECT id, name, created_at FROM public.clients;

GRANT SELECT ON public.queue_clients TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.register_queue_client(
  p_id UUID,
  p_name TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_accuracy DOUBLE PRECISION,
  p_location_captured_at TIMESTAMPTZ,
  p_created_at TIMESTAMPTZ
)
RETURNS SETOF public.clients
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  INSERT INTO public.clients (
    id, name, lat, lng, location_accuracy_m,
    location_captured_at, created_at
  )
  VALUES (
    p_id, p_name, p_lat, p_lng, p_accuracy,
    p_location_captured_at, p_created_at
  )
  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name
  RETURNING *;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_queue_client(
  UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION,
  TIMESTAMPTZ, TIMESTAMPTZ
) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.broadcast_queue_client_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM realtime.send(
    jsonb_build_object('id', NEW.id),
    'queue_client_inserted',
    'waiting-room',
    false
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS queue_client_insert_broadcast ON public.clients;
CREATE TRIGGER queue_client_insert_broadcast
  AFTER INSERT ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.broadcast_queue_client_insert();