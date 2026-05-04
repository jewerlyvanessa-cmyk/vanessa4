--
-- PostgreSQL database dump
--

\restrict AL7lUIHxMCsELD4MN8harvWr0GCp5JHlOOXDb6dxgSgNXJVDeuPYjw3eMNvExke

-- Dumped from database version 16.11 (Homebrew)
-- Dumped by pg_dump version 16.11

-- Started on 2026-04-21 22:17:22 WIB

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 4 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- TOC entry 4069 (class 0 OID 0)
-- Dependencies: 4
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- TOC entry 242 (class 1255 OID 24936)
-- Name: generate_nota_order(bigint, text); Type: FUNCTION; Schema: public; Owner: macbookpro2019
--

CREATE FUNCTION public.generate_nota_order(p_branch_id bigint, p_order_type text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_initial TEXT;
  v_code TEXT;
  v_order_code TEXT;
  v_seq BIGINT;
BEGIN
  SELECT initials, code
  INTO v_initial, v_code
  FROM branches
  WHERE branch_id = p_branch_id;

  v_order_code := CASE p_order_type
    WHEN 'jual' THEN 'JL'
    WHEN 'buyback' THEN 'BB'
    WHEN 'service' THEN 'SV'
    WHEN 'custom' THEN 'CT'
    ELSE NULL
  END;

  IF v_order_code IS NULL THEN
    RAISE EXCEPTION 'Invalid order_type: %', p_order_type;
  END IF;

  v_seq := nextval('order_nota_seq');

  RETURN v_initial || '-' || v_code || '-' || v_order_code || '-' || LPAD(v_seq::TEXT, 8, '0');
END;
$$;


ALTER FUNCTION public.generate_nota_order(p_branch_id bigint, p_order_type text) OWNER TO macbookpro2019;

--
-- TOC entry 245 (class 1255 OID 24998)
-- Name: round_to_nearest_5000(numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.round_to_nearest_5000(amount numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    modulo_10000 NUMERIC;
BEGIN
    -- Calculate modulo 10000
    modulo_10000 := amount % 10000;

    -- Apply rounding logic matching frontend _roundToNearest5000 function
    IF modulo_10000 = 5000 THEN
        -- Exactly 5000, keep as is
        RETURN amount;
    ELSIF modulo_10000 < 5000 THEN
        -- Below 5000, round up to 5000
        RETURN amount - modulo_10000 + 5000;
    ELSE
        -- Above 5000, round up to next 10000
        RETURN amount - modulo_10000 + 10000;
    END IF;
END;
$$;


ALTER FUNCTION public.round_to_nearest_5000(amount numeric) OWNER TO postgres;

--
-- TOC entry 243 (class 1255 OID 16571)
-- Name: terbilang(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.terbilang(n bigint) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    satuan TEXT[] := ARRAY['', 'satu', 'dua', 'tiga', 'empat', 'lima', 'enam', 'tujuh', 'delapan', 'sembilan'];
    hasil TEXT := '';
BEGIN
    IF n = 0 THEN
        RETURN 'nol rupiah';
    ELSIF n < 10 THEN
        hasil := satuan[n+1];
    ELSIF n < 20 THEN
        hasil := satuan[n-10+1] || ' belas';
    ELSIF n < 100 THEN
        hasil := satuan[(n/10)::int+1] || ' puluh ' || satuan[(n%10)+1];
    ELSIF n < 200 THEN
        hasil := 'seratus ' || terbilang(n-100);
    ELSIF n < 1000 THEN
        hasil := satuan[(n/100)::int+1] || ' ratus ' || terbilang(n%100);
    ELSIF n < 2000 THEN
        hasil := 'seribu ' || terbilang(n-1000);
    ELSIF n < 1000000 THEN
        hasil := terbilang(n/1000) || ' ribu ' || terbilang(n%1000);
    ELSIF n < 1000000000 THEN
        hasil := terbilang(n/1000000) || ' juta ' || terbilang(n%1000000);
    ELSE
        hasil := 'terlalu besar';
    END IF;
    RETURN trim(hasil) || ' rupiah';
END;
$$;


ALTER FUNCTION public.terbilang(n bigint) OWNER TO postgres;

--
-- TOC entry 244 (class 1255 OID 25055)
-- Name: update_item_conditions_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_item_conditions_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_item_conditions_updated_at() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 218 (class 1259 OID 16482)
-- Name: branches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.branches (
    branch_id bigint NOT NULL,
    name text NOT NULL,
    code text NOT NULL,
    alias text,
    initials text,
    address text,
    phone_number text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    status text DEFAULT 'active'::text,
    CONSTRAINT branches_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])))
);


ALTER TABLE public.branches OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 16481)
-- Name: branches_branch_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.branches_branch_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.branches_branch_id_seq OWNER TO postgres;

--
-- TOC entry 4070 (class 0 OID 0)
-- Dependencies: 217
-- Name: branches_branch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.branches_branch_id_seq OWNED BY public.branches.branch_id;


--
-- TOC entry 228 (class 1259 OID 16577)
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customers (
    customer_id bigint NOT NULL,
    name text NOT NULL,
    phone text,
    address text,
    metadata jsonb,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    branch_id bigint
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 16576)
-- Name: customers_customer_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.customers_customer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customers_customer_id_seq OWNER TO postgres;

--
-- TOC entry 4071 (class 0 OID 0)
-- Dependencies: 227
-- Name: customers_customer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.customers_customer_id_seq OWNED BY public.customers.customer_id;


--
-- TOC entry 239 (class 1259 OID 25023)
-- Name: item_conditions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.item_conditions (
    condition_id bigint NOT NULL,
    item_id bigint,
    order_id bigint,
    kondisi_fisik text,
    kerusakan text[],
    berat_awal numeric(10,2),
    berat_akhir numeric(10,2),
    penyesuaian_berat text,
    keaslian text,
    sertifikat text,
    nilai_resale bigint,
    harga_beli bigint,
    catatan_kondisi text,
    foto_kondisi text[],
    dinilai_oleh bigint,
    tanggal_penilaian timestamp without time zone DEFAULT now(),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT item_conditions_keaslian_check CHECK ((keaslian = ANY (ARRAY['ASLI'::text, 'KW'::text, 'TIDAK_DIKETAHUI'::text]))),
    CONSTRAINT item_conditions_kondisi_fisik_check CHECK ((kondisi_fisik = ANY (ARRAY['BAIK'::text, 'RUSAK_RINGAN'::text, 'RUSAK_BERAT'::text, 'RUSAK_PARAH'::text]))),
    CONSTRAINT item_conditions_sertifikat_check CHECK ((sertifikat = ANY (ARRAY['ADA'::text, 'TIDAK_ADA'::text, 'TIDAK_DIKETAHUI'::text])))
);


ALTER TABLE public.item_conditions OWNER TO postgres;

--
-- TOC entry 4072 (class 0 OID 0)
-- Dependencies: 239
-- Name: TABLE item_conditions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.item_conditions IS 'Stores detailed condition information for items in buyback orders';


--
-- TOC entry 238 (class 1259 OID 25022)
-- Name: item_conditions_condition_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.item_conditions_condition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.item_conditions_condition_id_seq OWNER TO postgres;

--
-- TOC entry 4073 (class 0 OID 0)
-- Dependencies: 238
-- Name: item_conditions_condition_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.item_conditions_condition_id_seq OWNED BY public.item_conditions.condition_id;


--
-- TOC entry 222 (class 1259 OID 16515)
-- Name: items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.items (
    item_id bigint NOT NULL,
    name text NOT NULL,
    weight numeric,
    material text,
    purity text,
    status text NOT NULL,
    branch_id bigint NOT NULL,
    metadata jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    kategori text,
    jenis text,
    tipe text,
    kode_produk text NOT NULL,
    qr_code text,
    quantity integer DEFAULT 1,
    ownership text DEFAULT 'unknown'::text,
    stock_type text DEFAULT 'non_inventory'::text,
    is_quick_registered boolean DEFAULT false,
    is_estimated boolean DEFAULT false,
    source text DEFAULT 'manual'::text,
    photo_url text,
    CONSTRAINT items_ownership_check CHECK ((ownership = ANY (ARRAY['toko'::text, 'pelanggan'::text, 'unknown'::text]))),
    CONSTRAINT items_stock_type_check CHECK ((stock_type = ANY (ARRAY['inventory'::text, 'non_inventory'::text])))
);


ALTER TABLE public.items OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16514)
-- Name: items_item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.items_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.items_item_id_seq OWNER TO postgres;

--
-- TOC entry 4074 (class 0 OID 0)
-- Dependencies: 221
-- Name: items_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.items_item_id_seq OWNED BY public.items.item_id;


--
-- TOC entry 241 (class 1259 OID 25060)
-- Name: order_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_items (
    order_item_id bigint NOT NULL,
    order_id bigint,
    item_id bigint,
    nama_item text,
    kode_produk text,
    weight numeric(10,2),
    qty integer DEFAULT 1,
    harga_per_gram numeric(10,2),
    material text,
    purity text,
    kategori text,
    jenis text,
    tipe text,
    subtotal numeric(10,2),
    total numeric(10,2),
    diskon numeric(10,2) DEFAULT 0,
    kondisi_barang jsonb,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    photo_produk text
);


ALTER TABLE public.order_items OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 25059)
-- Name: order_items_order_item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.order_items_order_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.order_items_order_item_id_seq OWNER TO postgres;

--
-- TOC entry 4075 (class 0 OID 0)
-- Dependencies: 240
-- Name: order_items_order_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.order_items_order_item_id_seq OWNED BY public.order_items.order_item_id;


--
-- TOC entry 237 (class 1259 OID 24935)
-- Name: order_nota_seq; Type: SEQUENCE; Schema: public; Owner: macbookpro2019
--

CREATE SEQUENCE public.order_nota_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.order_nota_seq OWNER TO macbookpro2019;

--
-- TOC entry 224 (class 1259 OID 16531)
-- Name: orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.orders (
    order_id bigint NOT NULL,
    order_type text NOT NULL,
    branch_id bigint,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    diskon numeric(5,2),
    total numeric(15,2),
    mode character varying,
    customer_id integer,
    user_id bigint NOT NULL,
    order_number text,
    status text DEFAULT 'draft'::text,
    jumlah numeric(15,2) DEFAULT 0,
    CONSTRAINT orders_order_type_check CHECK ((order_type = ANY (ARRAY['jual'::text, 'buyback'::text, 'service'::text, 'custom'::text]))),
    CONSTRAINT orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'pending'::text, 'completed'::text, 'cancelled'::text])))
);


ALTER TABLE public.orders OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 16530)
-- Name: orders_order_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.orders_order_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.orders_order_id_seq OWNER TO postgres;

--
-- TOC entry 4076 (class 0 OID 0)
-- Dependencies: 223
-- Name: orders_order_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.orders_order_id_seq OWNED BY public.orders.order_id;


--
-- TOC entry 232 (class 1259 OID 16638)
-- Name: payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payments (
    payment_id bigint NOT NULL,
    order_id bigint NOT NULL,
    amount numeric NOT NULL,
    method text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    payment_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    notes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT payments_method_check CHECK ((method = ANY (ARRAY['cash'::text, 'transfer'::text, 'qris'::text, 'e-wallet'::text]))),
    CONSTRAINT payments_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])))
);


ALTER TABLE public.payments OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 16637)
-- Name: payments_payment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.payments_payment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.payments_payment_id_seq OWNER TO postgres;

--
-- TOC entry 4077 (class 0 OID 0)
-- Dependencies: 231
-- Name: payments_payment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.payments_payment_id_seq OWNED BY public.payments.payment_id;


--
-- TOC entry 226 (class 1259 OID 16552)
-- Name: stock_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_history (
    history_id bigint NOT NULL,
    item_id bigint,
    old_status text NOT NULL,
    new_status text NOT NULL,
    changed_by bigint,
    notes text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.stock_history OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16551)
-- Name: stock_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.stock_history_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stock_history_history_id_seq OWNER TO postgres;

--
-- TOC entry 4078 (class 0 OID 0)
-- Dependencies: 225
-- Name: stock_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stock_history_history_id_seq OWNED BY public.stock_history.history_id;


--
-- TOC entry 236 (class 1259 OID 16705)
-- Name: stock_mutations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_mutations (
    mutation_id bigint NOT NULL,
    item_id bigint,
    branch_id bigint,
    type text NOT NULL,
    quantity integer NOT NULL,
    previous_stock integer,
    current_stock integer,
    notes text,
    reference_id bigint,
    reference_type text,
    created_by bigint,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT stock_mutations_type_check CHECK ((type = ANY (ARRAY['in'::text, 'out'::text, 'transfer'::text, 'adjustment'::text])))
);


ALTER TABLE public.stock_mutations OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 16704)
-- Name: stock_mutations_mutation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.stock_mutations_mutation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stock_mutations_mutation_id_seq OWNER TO postgres;

--
-- TOC entry 4079 (class 0 OID 0)
-- Dependencies: 235
-- Name: stock_mutations_mutation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stock_mutations_mutation_id_seq OWNED BY public.stock_mutations.mutation_id;


--
-- TOC entry 234 (class 1259 OID 16663)
-- Name: transfers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.transfers (
    transfer_id bigint NOT NULL,
    from_branch_id bigint,
    to_branch_id bigint,
    item_name text NOT NULL,
    quantity integer NOT NULL,
    notes text,
    order_id bigint,
    status text DEFAULT 'pending'::text NOT NULL,
    created_by bigint,
    approved_by bigint,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT transfers_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'completed'::text, 'rejected'::text])))
);


ALTER TABLE public.transfers OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 16662)
-- Name: transfers_transfer_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.transfers_transfer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.transfers_transfer_id_seq OWNER TO postgres;

--
-- TOC entry 4080 (class 0 OID 0)
-- Dependencies: 233
-- Name: transfers_transfer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.transfers_transfer_id_seq OWNED BY public.transfers.transfer_id;


--
-- TOC entry 230 (class 1259 OID 16612)
-- Name: uploaded_files; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.uploaded_files (
    id integer NOT NULL,
    filename text NOT NULL,
    url text NOT NULL,
    uploaded_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.uploaded_files OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 16611)
-- Name: uploaded_files_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.uploaded_files_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.uploaded_files_id_seq OWNER TO postgres;

--
-- TOC entry 4081 (class 0 OID 0)
-- Dependencies: 229
-- Name: uploaded_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.uploaded_files_id_seq OWNED BY public.uploaded_files.id;


--
-- TOC entry 220 (class 1259 OID 16495)
-- Name: user_branch_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_branch_roles (
    id bigint NOT NULL,
    user_id bigint,
    branch_id bigint,
    role text NOT NULL,
    is_primary boolean DEFAULT false
);


ALTER TABLE public.user_branch_roles OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 16494)
-- Name: user_branch_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_branch_roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_branch_roles_id_seq OWNER TO postgres;

--
-- TOC entry 4082 (class 0 OID 0)
-- Dependencies: 219
-- Name: user_branch_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_branch_roles_id_seq OWNED BY public.user_branch_roles.id;


--
-- TOC entry 216 (class 1259 OID 16469)
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    user_id bigint NOT NULL,
    username text NOT NULL,
    password_hash text NOT NULL,
    status text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.users OWNER TO postgres;

--
-- TOC entry 215 (class 1259 OID 16468)
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_user_id_seq OWNER TO postgres;

--
-- TOC entry 4083 (class 0 OID 0)
-- Dependencies: 215
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_user_id_seq OWNED BY public.users.user_id;


--
-- TOC entry 3741 (class 2604 OID 16485)
-- Name: branches branch_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.branches ALTER COLUMN branch_id SET DEFAULT nextval('public.branches_branch_id_seq'::regclass);


--
-- TOC entry 3763 (class 2604 OID 16580)
-- Name: customers customer_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers ALTER COLUMN customer_id SET DEFAULT nextval('public.customers_customer_id_seq'::regclass);


--
-- TOC entry 3779 (class 2604 OID 25026)
-- Name: item_conditions condition_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_conditions ALTER COLUMN condition_id SET DEFAULT nextval('public.item_conditions_condition_id_seq'::regclass);


--
-- TOC entry 3747 (class 2604 OID 16518)
-- Name: items item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items ALTER COLUMN item_id SET DEFAULT nextval('public.items_item_id_seq'::regclass);


--
-- TOC entry 3783 (class 2604 OID 25063)
-- Name: order_items order_item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items ALTER COLUMN order_item_id SET DEFAULT nextval('public.order_items_order_item_id_seq'::regclass);


--
-- TOC entry 3756 (class 2604 OID 16534)
-- Name: orders order_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders ALTER COLUMN order_id SET DEFAULT nextval('public.orders_order_id_seq'::regclass);


--
-- TOC entry 3768 (class 2604 OID 16641)
-- Name: payments payment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments ALTER COLUMN payment_id SET DEFAULT nextval('public.payments_payment_id_seq'::regclass);


--
-- TOC entry 3761 (class 2604 OID 16555)
-- Name: stock_history history_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_history ALTER COLUMN history_id SET DEFAULT nextval('public.stock_history_history_id_seq'::regclass);


--
-- TOC entry 3777 (class 2604 OID 16708)
-- Name: stock_mutations mutation_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_mutations ALTER COLUMN mutation_id SET DEFAULT nextval('public.stock_mutations_mutation_id_seq'::regclass);


--
-- TOC entry 3773 (class 2604 OID 16666)
-- Name: transfers transfer_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers ALTER COLUMN transfer_id SET DEFAULT nextval('public.transfers_transfer_id_seq'::regclass);


--
-- TOC entry 3766 (class 2604 OID 16615)
-- Name: uploaded_files id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uploaded_files ALTER COLUMN id SET DEFAULT nextval('public.uploaded_files_id_seq'::regclass);


--
-- TOC entry 3745 (class 2604 OID 16498)
-- Name: user_branch_roles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_branch_roles ALTER COLUMN id SET DEFAULT nextval('public.user_branch_roles_id_seq'::regclass);


--
-- TOC entry 3738 (class 2604 OID 16472)
-- Name: users user_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN user_id SET DEFAULT nextval('public.users_user_id_seq'::regclass);


--
-- TOC entry 4040 (class 0 OID 16482)
-- Dependencies: 218
-- Data for Name: branches; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.branches (branch_id, name, code, alias, initials, address, phone_number, created_at, updated_at, status) FROM stdin;
1	Toko Emas Vanessa Brangkal	BRG	Emas Brangkal	BGE	Pasar Brangkal	09888888	2025-12-26 22:39:47.854303	2025-12-26 22:39:47.854303	active
3	Workshop Vanessa Kendalsari	WKS	Bengkel Kendalsari	WKS	Kendalsari	088888888888	2025-12-28 13:31:29.581898	2025-12-28 13:31:29.581898	active
4	Cabang Utama	MAIN	Main Branch	CUT	Jl. Raya No. 123	\N	2026-01-04 15:13:25.314928	2026-01-04 15:13:25.314928	active
2	Toko Emas Vanessa Pohjejer	444	\N	\N	Pasar Pohjejer	\N	2025-12-27 22:29:45.78485	2026-04-14 22:37:01.084316	active
19	ggg	GDGD	ddseed	FFAS	ddege	4343435r3	2026-04-14 22:40:12.348334	2026-04-14 22:40:12.348334	active
7	Test Branch	TEST	Test Branch Alias	UI	Test Address 123	08123456789	2026-01-04 22:32:57.505659	2026-04-14 22:40:25.974097	active
\.


--
-- TOC entry 4050 (class 0 OID 16577)
-- Dependencies: 228
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customers (customer_id, name, phone, address, metadata, created_at, updated_at, branch_id) FROM stdin;
5	iwan_satu	09999	sooko	\N	2026-01-06 12:29:05.524903	2026-01-06 12:29:05.524903	\N
6	Test Customer	123456789	Test Address	\N	2026-01-07 09:16:24.405421	2026-01-07 09:16:24.405421	\N
7	Test Customer 2	123456789	Test Address	\N	2026-01-07 13:56:26.854901	2026-01-07 13:56:26.854901	\N
3	aku	22222	\N	\N	2025-12-31 12:14:48.416372	2025-12-31 12:14:48.416372	1
2	Jane Doe	9876543210		\N	2025-12-30 08:58:27.45348	2025-12-30 08:58:27.45348	1
4	anam	09999999	jakarta	\N	2026-01-01 00:30:47.393301	2026-01-12 23:30:10.391863	\N
1	John Doe	1234567890	Semarang	\N	2025-12-30 08:49:43.285388	2026-01-12 23:30:30.921302	1
8	Test Customer	08123456789	Test Address	\N	2026-02-21 00:00:51.909211	2026-02-21 00:00:51.909211	\N
9	Test Customer	08123456789	Test Address	\N	2026-03-01 22:24:25.961884	2026-03-01 22:24:25.961884	\N
10	Test Customer 3	08123456789	Test Address	\N	2026-03-01 22:28:17.808727	2026-03-01 22:28:17.808727	\N
11	Test Customer API	08123456789	Test Address API	\N	2026-03-01 22:49:53.119239	2026-03-01 22:49:53.119239	\N
12	gio	999	aaa	\N	2026-03-01 22:51:54.53481	2026-03-01 22:51:54.53481	\N
13	gio	000	aaa	\N	2026-03-01 22:52:12.047495	2026-03-01 22:52:12.047495	\N
14	gio	888	xxx	\N	2026-03-01 22:52:44.91655	2026-03-01 22:52:44.91655	\N
15	jaya	000	992	\N	2026-03-01 23:25:41.08705	2026-03-01 23:25:41.08705	\N
16	mamat	09090909	sooko	\N	2026-04-12 23:41:21.247664	2026-04-12 23:41:21.247664	\N
17	iman	000000	japan	\N	2026-04-12 23:44:45.470567	2026-04-12 23:44:45.470567	\N
18	bagus	09812256	gede	\N	2026-04-14 22:48:32.149839	2026-04-14 22:48:32.149839	\N
\.


--
-- TOC entry 4061 (class 0 OID 25023)
-- Dependencies: 239
-- Data for Name: item_conditions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.item_conditions (condition_id, item_id, order_id, kondisi_fisik, kerusakan, berat_awal, berat_akhir, penyesuaian_berat, keaslian, sertifikat, nilai_resale, harga_beli, catatan_kondisi, foto_kondisi, dinilai_oleh, tanggal_penilaian, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 4044 (class 0 OID 16515)
-- Dependencies: 222
-- Data for Name: items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.items (item_id, name, weight, material, purity, status, branch_id, metadata, created_at, updated_at, kategori, jenis, tipe, kode_produk, qr_code, quantity, ownership, stock_type, is_quick_registered, is_estimated, source, photo_url) FROM stdin;
6	Test Item	10.5	\N	\N	sold	1	\N	2026-01-16 11:16:36.881049	2026-01-16 11:16:36.881049	emas	anting	putih	TEST001	\N	1	pelanggan	non_inventory	f	f	manual	\N
18	Cinncin Tunanga	4	\N	\N	sold	1	\N	2026-02-08 09:56:10.542714	2026-02-08 09:56:10.542714	PERHIASAN	CINCIN	BIASA	9199	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1770519370405-967780451-8bf077d8-396a-4ef1-a34d-53b5490b47b31280709800342521887_compressed.jpg
12	Debug Test Item	5	\N	\N	sold	1	\N	2026-01-17 23:24:56.865533	2026-01-17 23:24:56.865533	PERHIASAN	CINCIN	EMAS	DEBUG-001	\N	1	pelanggan	non_inventory	f	f	manual	debug.jpg
14	Test Gold Ring Ready	5.5	emas	24k	sold	1	\N	2026-01-17 23:42:43.087506	2026-01-17 23:43:08.640752	PERHIASAN	CINCIN	EMAS	TEST-READY-1768668163086	\N	1	pelanggan	non_inventory	f	f	manual	test-photo.jpg
2	gelang	2.2	Emas	22	sold	1	\N	2026-01-01 06:20:14.464412	2026-01-20 21:57:19.478087	Perhiasan	Gelang	Gress	2211	\N	1	pelanggan	non_inventory	f	f	manual	\N
16	Test Item	1	\N	\N	sold	3	\N	2026-01-21 07:59:59.742968	2026-01-21 07:59:59.742968	PERHIASAN	KALUNG	BIASA	TEST123	\N	1	pelanggan	non_inventory	f	f	manual	http://localhost:4000/uploads/test.jpg
1	Kalung Rantai	1.2	Emas	8	sold	1	\N	2026-01-01 05:16:47.000893	2026-01-21 08:21:53.096524	Perhiasan	Kalung	Biasa	2123	\N	1	pelanggan	non_inventory	f	f	manual	\N
17	Cincin Tunangan Cewek	3	\N	\N	sold	1	\N	2026-01-25 23:20:06.805285	2026-01-25 23:20:06.805285	PERHIASAN	CINCIN	BIASA	3214	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1769358006671-299120019-4a86c6b7-4bcd-48b3-9293-9da4bdee50b12713237126349160429_compressed.jpg
26	Cincin Tunangan	9	\N	\N	sold	1	\N	2026-02-17 09:34:46.018916	2026-02-17 09:34:46.018916	PERHIASAN		BIASA	19882	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771295685921-313339141-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg
27	Gelang Rantai	22	\N	\N	sold	1	\N	2026-02-17 09:38:17.205839	2026-02-17 09:38:17.205839	PERHIASAN	GELANG	BIASA	198721	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771295897126-678923464-08cfad73-9863-4168-baa5-63de6deee7e45483954934886774672_compressed.jpg
28	Test API Gold Ring	10.5	GOLD 18K	18K	sold	1	\N	2026-02-17 09:42:19.184346	2026-02-17 09:42:19.184346	PERHIASAN	CINCIN	EMAS	TEST-API-001	\N	1	pelanggan	non_inventory	f	f	manual	api-test-photo.jpg
29	anting bandul	19	\N	\N	sold	1	\N	2026-02-17 09:43:24.559208	2026-02-17 09:43:24.559208	PERHIASAN	ANTING	BIASA	2918	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771296204509-356756407-605128b8-55f4-4c2f-a7e1-7da0252d2ea38113452595898263251_compressed.jpg
30	Test Debug Gold Ring	8.5	GOLD 22K	22K	sold	1	\N	2026-02-17 09:44:43.651122	2026-02-17 09:44:43.651122	PERHIASAN	CINCIN	EMAS	TEST-DEBUG-001	\N	1	pelanggan	non_inventory	f	f	manual	debug-test-photo.jpg
31	Test Debug2 Gold Ring	7.5	GOLD 24K	24K	sold	1	\N	2026-02-17 09:45:06.28981	2026-02-17 09:45:06.28981	PERHIASAN	CINCIN	EMAS	TEST-DEBUG2-001	\N	1	pelanggan	non_inventory	f	f	manual	debug2-test-photo.jpg
32	Kalung Restra	19	Emas	22	sold	1	\N	2026-02-17 09:51:40.810068	2026-02-17 09:51:40.810068	PERHIASAN	KALUNG	BIASA	9913	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771296700752-14272089-78fca1eb-edbc-403e-91ed-d1cd928c2d785574261746705918610_compressed.jpg
33	Cincin Kawin	9	Emas	18	sold	1	\N	2026-02-19 21:50:23.403102	2026-02-20 22:48:00.657843	PERHIASAN	CINCIN	BIASA	9812	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771512623293-669832820-cf61bbaa-e04d-4277-9b5a-65ff446c79f22224684779849167315_compressed.jpg
34	Anting Bandul	12	Emas	22	sold	1	\N	2026-02-20 22:54:29.624435	2026-02-20 22:56:33.045432	PERHIASAN	ANTING	BIASA	19994	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771602869460-603541159-64635c0f-2375-40ee-9587-4b63b78bc8486880528635135730139_compressed.jpg
35	Anting Logam	9	Emas	18	sold	1	\N	2026-02-20 23:01:09.97558	2026-02-20 23:03:31.639921	PERHIASAN	ANTING	BIASA	09876	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771603269854-785206434-2072a978-23f2-452f-8784-95d4e605fd0a2853489103302423153_compressed.jpg
36	Gelang Kriwil	7	Emas	18	sold	1	\N	2026-02-20 23:14:36.932601	2026-02-20 23:14:36.932601	PERHIASAN	GELANG	BIASA	9976	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771604076738-438334243-d0bda1c3-ec4a-4317-bc1b-a8593ba118d34667942638837181606_compressed.jpg
37	Kalung Rantai	9	Emas	12	sold	1	\N	2026-02-20 23:32:35.531882	2026-02-20 23:32:35.531882	PERHIASAN	KALUNG	BIASA	12345	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771605155413-194319237-b57d591b-c1de-4fc5-a269-1560eb7520f14573410742959882402_compressed.jpg
38	gelang usus	8	Emas	18	sold	1	\N	2026-02-20 23:35:45.188891	2026-02-20 23:35:45.188891	PERHIASAN	GELANG	BIASA	124121	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771605345098-972244640-0ef04193-82c7-4864-952f-8a3797df7faa2999963801905726293_compressed.jpg
40	Gelang Bayi Polos	2	Emas	18	sold	1	\N	2026-02-20 23:41:30.586535	2026-02-20 23:41:30.586535	PERHIASAN		BIASA	0009999	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1771605690531-417487211-6f2b38e4-1421-4bb8-b33c-7d89c40329e37362949465524025492_compressed.jpg
41	gelang bayi	2	Emas	12	sold	1	\N	2026-03-01 23:26:27.147535	2026-03-01 23:26:27.147535	PERHIASAN	GELANG	BIASA	212334	\N	1	pelanggan	non_inventory	f	f	manual	http://10.0.2.2:4000/uploads/1772382387022-982052689-e4f0cb52-cc23-4833-a55b-8fd7f264447e2817965383034992375_compressed.jpg
42	gelang ulir	2	Emas	12	sold	1	\N	2026-03-02 00:28:59.056714	2026-03-02 00:28:59.056714	PERHIASAN	GELANG	BIASA	2213	\N	1	pelanggan	non_inventory	f	f	manual	\N
43	gelang 123	3	Emas	12	sold	1	\N	2026-03-05 23:05:30.311806	2026-03-05 23:05:30.311806	PERHIASAN	GELANG	BIASA	411112	\N	1	pelanggan	non_inventory	f	f	manual	\N
44	liontin giok merah	4	giok	100	sold	1	\N	2026-04-12 23:42:39.332876	2026-04-12 23:42:39.332876	PERHIASAN	LIONTIN	BIASA	9999	\N	1	pelanggan	non_inventory	f	f	manual	\N
45	Gelang Mutiara	8.2	Emas	18	sold	1	\N	2026-04-12 23:47:08.025295	2026-04-12 23:47:08.025295	PERHIASAN	GELANG	GRESS	121212	\N	1	pelanggan	non_inventory	f	f	manual	\N
46	anting bandul	2.7	Emas	18	sold	1	\N	2026-04-15 08:03:59.845593	2026-04-15 08:03:59.845593	PERHIASAN	ANTING	BIASA	001	\N	1	pelanggan	non_inventory	f	f	manual	\N
\.


--
-- TOC entry 4063 (class 0 OID 25060)
-- Dependencies: 241
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_items (order_item_id, order_id, item_id, nama_item, kode_produk, weight, qty, harga_per_gram, material, purity, kategori, jenis, tipe, subtotal, total, diskon, kondisi_barang, created_at, updated_at, photo_produk) FROM stdin;
1	155	\N	Cincin Emas	PRD-001	5.50	1	1000000.00	Emas	24K	PERHIASAN	CINCIN	BIASA	5500000.00	5500000.00	0.00	\N	2026-02-17 09:22:42.440339	2026-02-17 09:22:42.440339	\N
2	164	\N	Test Gold Ring	TEST-RING-001	5.55	1	1000000.00	\N	\N	PERHIASAN	CINCIN	EMAS	5550000.00	5272500.00	5.00	\N	2026-02-17 09:34:22.430059	2026-02-17 09:34:22.430059	test-photo-url.jpg
3	165	26	Cincin Tunangan	19882	9.00	1	250000.00	\N	\N	PERHIASAN		BIASA	2250000.00	2250000.00	0.00	\N	2026-02-17 09:34:46.018916	2026-02-17 09:34:46.018916	http://10.0.2.2:4000/uploads/1771295685921-313339141-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg
4	166	27	Gelang Rantai	198721	22.00	1	900000.00	\N	\N	PERHIASAN	GELANG	BIASA	19800000.00	19800000.00	0.00	\N	2026-02-17 09:38:17.205839	2026-02-17 09:38:17.205839	http://10.0.2.2:4000/uploads/1771295897126-678923464-08cfad73-9863-4168-baa5-63de6deee7e45483954934886774672_compressed.jpg
5	167	\N	Test Gold Ring with Material	TEST-RING-MAT-001	5.00	1	1000000.00	GOLD	24K	PERHIASAN	CINCIN	EMAS	5000000.00	5000000.00	0.00	\N	2026-02-17 09:41:43.902249	2026-02-17 09:41:43.902249	test-photo-url.jpg
6	168	28	Test API Gold Ring	TEST-API-001	10.50	1	950000.00	\N	\N	PERHIASAN	CINCIN	EMAS	9975000.00	9975000.00	0.00	\N	2026-02-17 09:42:19.184346	2026-02-17 09:42:19.184346	api-test-photo.jpg
7	169	29	anting bandul	2918	19.00	1	900000.00	\N	\N	PERHIASAN	ANTING	BIASA	17100000.00	17100000.00	0.00	\N	2026-02-17 09:43:24.559208	2026-02-17 09:43:24.559208	http://10.0.2.2:4000/uploads/1771296204509-356756407-605128b8-55f4-4c2f-a7e1-7da0252d2ea38113452595898263251_compressed.jpg
8	170	30	Test Debug Gold Ring	TEST-DEBUG-001	8.50	1	900000.00	\N	\N	PERHIASAN	CINCIN	EMAS	7650000.00	7650000.00	0.00	\N	2026-02-17 09:44:43.651122	2026-02-17 09:44:43.651122	debug-test-photo.jpg
9	171	31	Test Debug2 Gold Ring	TEST-DEBUG2-001	7.50	1	850000.00	\N	\N	PERHIASAN	CINCIN	EMAS	6375000.00	6375000.00	0.00	\N	2026-02-17 09:45:06.28981	2026-02-17 09:45:06.28981	debug2-test-photo.jpg
10	172	\N	Test Final3 Gold Ring	TEST-FINAL3-001	9.50	1	750000.00	GOLD 14K	14K	PERHIASAN	CINCIN	EMAS	7125000.00	7125000.00	0.00	\N	2026-02-17 09:47:50.143885	2026-02-17 09:47:50.143885	final3-test-photo.jpg
11	173	32	Kalung Restra	9913	19.00	1	299999.00	Emas	22	PERHIASAN	KALUNG	BIASA	5699981.00	5699981.00	0.00	\N	2026-02-17 09:51:40.810068	2026-02-17 09:51:40.810068	http://10.0.2.2:4000/uploads/1771296700752-14272089-78fca1eb-edbc-403e-91ed-d1cd928c2d785574261746705918610_compressed.jpg
12	174	33	Cincin Kawin	9812	9.00	1	900000.00	Emas	18	PERHIASAN	CINCIN	BIASA	8100000.00	8100000.00	0.00	\N	2026-02-19 21:50:23.403102	2026-02-19 21:50:23.403102	http://10.0.2.2:4000/uploads/1771512623293-669832820-cf61bbaa-e04d-4277-9b5a-65ff446c79f22224684779849167315_compressed.jpg
13	175	33	Cincin Kawin	9812	9.00	1	8100000.00	Emas	18	PERHIASAN	CINCIN	BIASA	8100000.00	8100000.00	0.00	\N	2026-02-20 22:48:00.657843	2026-02-20 22:48:00.657843	1771602480625-compressed_scaled_19b728da-5dc0-4a4f-bfc2-9bc61421f82e2799632454558161874.jpg
14	176	34	Anting Bandul	19994	12.00	1	919000.00	Emas	22	PERHIASAN	ANTING	BIASA	11028000.00	11028000.00	0.00	\N	2026-02-20 22:54:29.624435	2026-02-20 22:54:29.624435	http://10.0.2.2:4000/uploads/1771602869460-603541159-64635c0f-2375-40ee-9587-4b63b78bc8486880528635135730139_compressed.jpg
15	177	34	Anting Bandul	19994	12.00	1	11028000.00	Emas	22	PERHIASAN	ANTING	BIASA	11028000.00	11028000.00	0.00	\N	2026-02-20 22:56:33.045432	2026-02-20 22:56:33.045432	1771602993024-compressed_scaled_9e9a3cd7-4e13-4196-97ed-91a2ed7185778520263242554971790.jpg
16	178	35	Anting Logam	09876	9.00	1	919000.00	Emas	18	PERHIASAN	ANTING	BIASA	8271000.00	8271000.00	0.00	\N	2026-02-20 23:01:09.97558	2026-02-20 23:01:09.97558	http://10.0.2.2:4000/uploads/1771603269854-785206434-2072a978-23f2-452f-8784-95d4e605fd0a2853489103302423153_compressed.jpg
17	179	35	Anting Logam	09876	9.00	1	919000.00	Emas	18	PERHIASAN	ANTING	BIASA	8271000.00	8271000.00	0.00	\N	2026-02-20 23:03:31.639921	2026-02-20 23:03:31.639921	1771603411598-compressed_scaled_e26fd41d-0a5a-4b13-ab6d-06b42c5322dc2750428891870586172.jpg
18	180	36	Gelang Kriwil	9976	7.00	1	990000.00	Emas	18	PERHIASAN	GELANG	BIASA	6930000.00	6930000.00	0.00	\N	2026-02-20 23:14:36.932601	2026-02-20 23:14:36.932601	http://10.0.2.2:4000/uploads/1771604076738-438334243-d0bda1c3-ec4a-4317-bc1b-a8593ba118d34667942638837181606_compressed.jpg
19	181	37	Kalung Rantai	12345	9.00	1	900000.00	Emas	12	PERHIASAN	KALUNG	BIASA	8100000.00	8100000.00	0.00	\N	2026-02-20 23:32:35.531882	2026-02-20 23:32:35.531882	http://10.0.2.2:4000/uploads/1771605155413-194319237-b57d591b-c1de-4fc5-a269-1560eb7520f14573410742959882402_compressed.jpg
20	182	38	gelang usus	124121	8.00	1	920000.00	Emas	18	PERHIASAN	GELANG	BIASA	7360000.00	7360000.00	0.00	\N	2026-02-20 23:35:45.188891	2026-02-20 23:35:45.188891	http://10.0.2.2:4000/uploads/1771605345098-972244640-0ef04193-82c7-4864-952f-8a3797df7faa2999963801905726293_compressed.jpg
21	184	40	Gelang Bayi Polos	0009999	2.00	1	900000.00	Emas	18	PERHIASAN		BIASA	1800000.00	1800000.00	0.00	\N	2026-02-20 23:41:30.586535	2026-02-20 23:41:30.586535	http://10.0.2.2:4000/uploads/1771605690531-417487211-6f2b38e4-1421-4bb8-b33c-7d89c40329e37362949465524025492_compressed.jpg
22	185	41	gelang bayi	212334	2.00	1	999900.00	Emas	12	PERHIASAN	GELANG	BIASA	1999800.00	1999800.00	0.00	\N	2026-03-01 23:26:27.147535	2026-03-01 23:26:27.147535	http://10.0.2.2:4000/uploads/1772382387022-982052689-e4f0cb52-cc23-4833-a55b-8fd7f264447e2817965383034992375_compressed.jpg
23	186	42	gelang ulir	2213	2.00	1	9999300.00	Emas	12	PERHIASAN	GELANG	BIASA	19998600.00	19998600.00	0.00	\N	2026-03-02 00:28:59.056714	2026-03-02 00:28:59.056714	\N
24	187	43	gelang 123	411112	3.00	1	998725.00	Emas	12	PERHIASAN	GELANG	BIASA	2996175.00	2996175.00	0.00	\N	2026-03-05 23:05:30.311806	2026-03-05 23:05:30.311806	\N
25	188	44	liontin giok merah	9999	4.00	1	100000.00	giok	100	PERHIASAN	LIONTIN	BIASA	400000.00	400000.00	0.00	\N	2026-04-12 23:42:39.332876	2026-04-12 23:42:39.332876	\N
26	189	45	Gelang Mutiara	121212	8.20	1	1200000.00	Emas	18	PERHIASAN	GELANG	GRESS	9840000.00	9840000.00	0.00	\N	2026-04-12 23:47:08.025295	2026-04-12 23:47:08.025295	\N
27	190	46	anting bandul	001	2.70	1	1000000.00	Emas	18	PERHIASAN	ANTING	BIASA	2700000.00	2700000.00	0.00	\N	2026-04-15 08:03:59.845593	2026-04-15 08:03:59.845593	\N
\.


--
-- TOC entry 4046 (class 0 OID 16531)
-- Dependencies: 224
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (order_id, order_type, branch_id, created_at, updated_at, diskon, total, mode, customer_id, user_id, order_number, status, jumlah) FROM stdin;
133	jual	1	2026-01-20 22:12:34.65289	2026-01-20 22:12:34.65289	0.00	918960.00	TOKO	5	8	BGEJ21920630	draft	0.00
135	jual	1	2026-01-20 22:23:49.811491	2026-01-20 22:23:49.811491	0.00	1198800.00	TOKO	2	8	BGEJ22597661	draft	0.00
139	jual	3	2026-01-21 07:59:59.742968	2026-01-21 07:59:59.742968	0.00	100000.00	TOKO	5	8	TEST001	draft	0.00
141	jual	1	2026-01-21 08:21:53.096524	2026-01-21 08:21:53.096524	0.00	1185480.00	TOKO	2	8	BGEJ58483102	draft	0.00
142	jual	1	2026-01-25 23:20:06.805285	2026-01-25 23:20:06.805285	0.00	2803500.00	TOKO	5	8	BGEJ57921588	draft	0.00
155	jual	1	2026-02-08 09:56:10.542714	2026-02-08 11:24:07.440658	0.00	4800000.00	TOKO	3	8	BGEJ19304861	completed	0.00
53	jual	1	2026-01-01 11:35:22.988261	2026-01-01 11:35:22.988261	0.00	1080000.00	TOKO	\N	8	ORDER-53	draft	0.00
54	jual	1	2026-01-01 12:39:14.612659	2026-01-01 12:39:14.612659	0.00	108000.00	TOKO	\N	8	ORDER-54	draft	0.00
4	jual	1	2025-12-29 15:50:05.077907	2025-12-29 15:50:05.077907	0.00	1710000.00	TOKO	\N	6	ORDER-4	draft	0.00
5	jual	1	2025-12-29 15:50:05.114272	2025-12-29 15:50:05.114272	0.00	1710000.00	TOKO	\N	6	ORDER-5	draft	0.00
6	jual	1	2025-12-29 15:54:28.0673	2025-12-29 15:54:28.0673	0.00	1710000.00	TOKO	\N	6	ORDER-6	draft	0.00
7	jual	1	2025-12-29 15:56:24.721179	2025-12-29 15:56:24.721179	0.00	878000.00	TOKO	\N	6	ORDER-7	draft	0.00
31	jual	\N	2026-01-01 10:11:24.177212	2026-01-01 10:11:24.177212	0.00	1200.00	\N	\N	6	ORDER-31	draft	0.00
32	jual	\N	2026-01-01 10:11:30.891207	2026-01-01 10:11:30.891207	0.00	1200.00	\N	\N	6	ORDER-32	draft	0.00
33	jual	\N	2026-01-01 10:11:59.985393	2026-01-01 10:11:59.985393	0.00	1200.00	\N	\N	6	ORDER-33	draft	0.00
51	jual	1	2026-01-01 11:04:54.05038	2026-01-01 11:04:54.05038	0.00	1080000.00	\N	\N	6	ORDER-51	draft	0.00
52	jual	1	2026-01-01 11:07:07.833582	2026-01-01 11:07:07.833582	0.00	1080000.00	\N	\N	6	ORDER-52	draft	0.00
84	jual	1	2026-01-07 14:19:37.336123	2026-01-07 14:19:37.336123	0.00	2700000.00	\N	6	11	ORDER-84	draft	0.00
85	jual	1	2026-01-08 22:35:42.102099	2026-01-08 22:35:42.102099	0.00	180500.00	TOKO	3	8	ORDER-85	draft	0.00
165	jual	1	2026-02-17 09:34:46.018916	2026-04-15 08:01:01.061492	0.00	2250000.00	TOKO	2	8	BGEJ95359170	completed	0.00
167	jual	1	2026-02-17 09:41:43.902249	2026-02-17 09:41:43.902249	0.00	\N	TOKO	5	6	TEST-MATERIAL-1771296103894	draft	0.00
188	jual	1	2026-04-12 23:42:39.332876	2026-04-12 23:43:42.769248	0.00	400000.00	TOKO	16	8	BGEJ12056294	completed	0.00
186	jual	1	2026-03-02 00:28:59.056714	2026-03-02 12:36:06.091952	0.00	19998600.00	TOKO	12	8	BGEJ86035727	completed	0.00
101	jual	1	2026-01-17 22:24:59.738998	2026-01-17 22:24:59.738998	0.00	\N	TOKO	2	8	ORDER-101	draft	0.00
105	jual	1	2026-01-17 22:33:00.617768	2026-01-17 22:33:00.617768	0.00	\N	TOKO	3	8	ORDER-105	draft	0.00
1	jual	1	2025-12-29 15:40:15.576669	2025-12-29 15:40:15.576669	0.00	1800000.00	TOKO	1	6	ORDER-1	draft	0.00
2	jual	1	2025-12-29 15:48:32.196033	2025-12-29 15:48:32.196033	0.00	1800000.00	TOKO	1	6	ORDER-2	draft	0.00
3	jual	1	2025-12-29 15:49:42.939206	2025-12-29 15:49:42.939206	0.00	1710000.00	TOKO	1	6	ORDER-3	draft	0.00
86	jual	1	2026-01-11 11:45:36.21372	2026-01-11 11:45:36.21372	\N	\N	\N	1	6	ORDER-86	draft	0.00
87	service	1	2026-01-13 23:31:11.439899	2026-01-13 23:31:11.439899	0.00	900000.00	\N	1	6	ORDER-87	draft	0.00
93	jual	1	2026-01-16 11:16:36.881049	2026-01-16 11:16:36.881049	0.00	\N	TOKO	1	8	ORDER-93	draft	0.00
99	jual	1	2026-01-17 22:06:01.847416	2026-01-17 22:06:01.847416	0.00	\N	TOKO	2	8	ORDER-99	draft	0.00
100	jual	1	2026-01-17 22:06:47.316771	2026-01-17 22:06:47.316771	0.00	\N	TOKO	1	8	ORDER-100	draft	0.00
164	jual	1	2026-02-17 09:34:22.430059	2026-02-17 09:34:22.430059	5.00	\N	TOKO	5	6	TEST-1771295662412	draft	0.00
172	jual	1	2026-02-17 09:47:50.143885	2026-02-17 09:47:50.143885	0.00	\N	TOKO	5	6	TEST-FINAL3-1771296470133	draft	0.00
170	jual	1	2026-02-17 09:44:43.651122	2026-02-20 23:48:30.183523	0.00	7650000.00	TOKO	5	6	TEST-DEBUG-1771296283625	completed	0.00
181	jual	1	2026-02-20 23:32:35.531882	2026-02-20 23:33:21.409025	0.00	8100000.00	TOKO	5	8	BGEJ05094463	completed	0.00
174	jual	1	2026-02-19 21:50:23.403102	2026-02-19 22:04:51.562744	0.00	8100000.00	TOKO	2	8	BGEJ12565940	completed	0.00
171	jual	1	2026-02-17 09:45:06.28981	2026-02-19 22:11:37.647105	0.00	6375000.00	TOKO	5	6	TEST-DEBUG2-1771296306	completed	0.00
178	jual	1	2026-02-20 23:01:09.97558	2026-02-20 23:01:35.708247	0.00	8271000.00	TOKO	5	8	BGEJ03202580	completed	0.00
176	jual	1	2026-02-20 22:54:29.624435	2026-02-20 22:54:43.255306	0.00	11028000.00	TOKO	5	8	BGEJ02804132	completed	0.00
179	buyback	1	2026-02-20 23:03:31.639921	2026-02-20 23:07:39.409771	0.00	8271000.00	TOKO	5	8	BGEB03333014	completed	0.00
177	buyback	1	2026-02-20 22:56:33.045432	2026-02-20 23:11:26.262185	0.00	11028000.00	TOKO	5	8	BGEB02924067	completed	0.00
175	buyback	1	2026-02-20 22:48:00.657843	2026-02-20 23:11:45.337473	0.00	8100000.00	TOKO	2	8	BGEB02191444	completed	0.00
173	jual	1	2026-02-17 09:51:40.810068	2026-02-20 23:11:59.150845	0.00	5699981.00	TOKO	1	8	BGEJ96631913	completed	0.00
180	jual	1	2026-02-20 23:14:36.932601	2026-02-20 23:14:58.887577	0.00	6930000.00	TOKO	1	8	BGEJ04001686	completed	0.00
184	jual	1	2026-02-20 23:41:30.586535	2026-02-20 23:41:48.007439	0.00	1800000.00	TOKO	5	8	BGEJ05554796	completed	0.00
182	jual	1	2026-02-20 23:35:45.188891	2026-02-20 23:47:25.59089	0.00	7360000.00	TOKO	5	8	BGEJ05282605	completed	0.00
185	jual	1	2026-03-01 23:26:27.147535	2026-03-01 23:26:58.819887	0.00	1999800.00	TOKO	15	8	BGEJ82315023	completed	0.00
169	jual	1	2026-02-17 09:43:24.559208	2026-04-12 23:39:07.361435	0.00	17100000.00	TOKO	5	8	BGEJ96158641	completed	0.00
168	jual	1	2026-02-17 09:42:19.184346	2026-04-12 23:39:10.309123	0.00	9975000.00	TOKO	5	6	TEST-API-1771296139161	completed	0.00
187	jual	1	2026-03-05 23:05:30.311806	2026-04-12 23:39:03.490297	0.00	2996175.00	TOKO	5	8	BGEJ26669976	completed	0.00
166	jual	1	2026-02-17 09:38:17.205839	2026-04-15 08:00:59.248086	0.00	19800000.00	TOKO	3	8	BGEJ95826821	completed	0.00
189	jual	1	2026-04-12 23:47:08.025295	2026-04-15 08:00:56.384163	0.00	9840000.00	TOKO	17	8	BGEJ12345090	completed	0.00
190	jual	1	2026-04-15 08:03:59.845593	2026-04-15 08:03:59.845593	0.00	2700000.00	TOKO	5	23	BGEJ14800893	pending	0.00
134	jual	1	2026-01-20 22:19:43.606554	2026-01-20 22:19:43.606554	0.00	1198800.00	TOKO	3	8	BGEJ22351088	draft	0.00
138	jual	1	2026-01-21 07:52:30.517428	2026-01-21 07:52:30.517428	0.00	1311240.00	TOKO	5	8	BGEJ56708219	draft	0.00
140	jual	1	2026-01-21 08:20:40.620074	2026-01-21 08:20:40.620074	0.00	11762520.00	TOKO	3	8	BGEJ58401094	draft	0.00
76	jual	1	2026-01-02 04:37:59.842856	2026-01-02 04:37:59.842856	0.00	1530000.00	TOKO	\N	8	ORDER-76	draft	0.00
77	jual	1	2026-01-06 22:57:39.22701	2026-01-06 22:57:39.22701	0.00	1080000.00	TOKO	\N	8	ORDER-77	draft	0.00
78	jual	1	2026-01-06 23:14:07.776029	2026-01-06 23:14:07.776029	0.00	1800000.00	TOKO	\N	8	ORDER-78	draft	0.00
79	jual	1	2026-01-07 00:53:33.321725	2026-01-07 00:53:33.321725	0.00	1020000.00	TOKO	\N	8	ORDER-79	draft	0.00
81	jual	1	2026-01-07 13:54:34.33672	2026-01-07 13:54:34.33672	0.00	4500000.00	\N	6	11	ORDER-81	draft	0.00
82	jual	1	2026-01-07 13:56:26.857372	2026-01-07 13:56:26.857372	0.00	2700000.00	\N	7	11	ORDER-82	draft	0.00
83	jual	1	2026-01-07 14:15:02.868948	2026-01-07 14:15:02.868948	0.00	1920000.00	TOKO	3	8	ORDER-83	draft	0.00
106	jual	1	2026-01-17 22:42:54.120059	2026-01-17 22:42:54.120059	0.00	1185588.00	TOKO	5	8	BGEJ64541105	draft	0.00
107	jual	1	2026-01-17 22:46:16.314525	2026-01-17 22:46:16.314525	5.00	\N	TOKO	5	6	TEST-1768664776171	draft	0.00
109	jual	1	2026-01-17 22:57:57.181056	2026-01-17 22:57:57.181056	5.00	\N	TOKO	5	6	TEST-1768665477164	draft	0.00
110	jual	1	2026-01-17 23:04:25.636025	2026-01-17 23:04:25.636025	5.00	\N	TOKO	5	6	TEST-1768665865620	draft	0.00
111	jual	1	2026-01-17 23:07:51.435783	2026-01-17 23:07:51.435783	5.00	\N	TOKO	5	6	TEST-1768666071420	draft	0.00
112	jual	1	2026-01-17 23:11:05.273092	2026-01-17 23:11:05.273092	5.00	\N	TOKO	5	6	TEST-1768666265258	draft	0.00
113	jual	1	2026-01-17 23:12:33.500504	2026-01-17 23:12:33.500504	5.00	\N	TOKO	5	6	TEST-1768666353480	draft	0.00
114	jual	1	2026-01-17 23:20:56.209073	2026-01-17 23:20:56.209073	5.00	5272500.00	TOKO	5	6	TEST-1768666856193	draft	0.00
115	jual	1	2026-01-17 23:24:56.865533	2026-01-17 23:24:56.865533	5.00	4750000.00	TOKO	5	6	DEBUG-TEST	draft	0.00
117	jual	1	2026-01-17 23:26:40.096201	2026-01-17 23:26:40.096201	5.00	4750000.00	TOKO	5	6	SIMULATE-TEST	draft	0.00
118	jual	1	2026-01-17 23:27:17.576903	2026-01-17 23:27:17.576903	5.00	4750000.00	TOKO	5	6	TEST-NO-GENERATED	draft	0.00
119	jual	1	2026-01-17 23:28:16.125996	2026-01-17 23:28:16.125996	5.00	5272500.00	TOKO	5	6	TEST-1768667296103	draft	0.00
120	jual	1	2026-01-17 23:28:59.016896	2026-01-17 23:28:59.016896	5.00	\N	TOKO	5	6	TEST-1768667339001	draft	0.00
121	jual	1	2026-01-17 23:30:50.971161	2026-01-17 23:30:50.971161	5.00	\N	TOKO	5	6	TEST-1768667450955	draft	0.00
122	jual	1	2026-01-17 23:31:15.759627	2026-01-17 23:31:15.759627	5.00	9999999.00	TOKO	5	6	TEST-1768667475744	draft	0.00
123	jual	1	2026-01-17 23:32:10.175858	2026-01-17 23:32:10.175858	5.00	\N	TOKO	5	6	TEST-1768667530157	draft	0.00
124	jual	1	2026-01-17 23:33:37.098888	2026-01-17 23:33:37.098888	5.00	\N	TOKO	5	6	TEST-1768667617083	draft	0.00
125	jual	1	2026-01-17 23:34:54.123517	2026-01-17 23:34:54.123517	0.00	922800.00	TOKO	5	8	BGEJ67661670	draft	0.00
126	jual	1	2026-01-17 23:43:08.640752	2026-01-17 23:43:08.640752	0.00	5500000.00	TOKO	5	6	TEST-STOCK-1768668188629	draft	0.00
132	jual	1	2026-01-20 21:57:19.478087	2026-01-20 21:57:19.478087	0.00	2032250.00	TOKO	1	8	BGEJ20996607	draft	0.00
131	jual	1	2026-01-19 11:22:30.924903	2026-01-19 11:22:30.924903	0.00	1979340.00	TOKO	4	8	BGEJ96507660	draft	0.00
\.


--
-- TOC entry 4054 (class 0 OID 16638)
-- Dependencies: 232
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payments (payment_id, order_id, amount, method, status, payment_date, notes, created_at, updated_at) FROM stdin;
1	155	4800000	qris	completed	2026-02-08 10:48:45.396934		2026-02-08 10:48:45.396934	2026-02-08 10:48:45.396934
2	155	4800000	cash	completed	2026-02-08 10:48:52.069432		2026-02-08 10:48:52.069432	2026-02-08 10:48:52.069432
3	155	4800000	cash	completed	2026-02-08 11:24:07.438673	\N	2026-02-08 11:24:07.438673	2026-02-08 11:24:07.438673
4	174	8100000	cash	completed	2026-02-19 22:04:51.560696		2026-02-19 22:04:51.560696	2026-02-19 22:04:51.560696
5	171	6375000	cash	completed	2026-02-19 22:11:37.645404		2026-02-19 22:11:37.645404	2026-02-19 22:11:37.645404
6	176	11028000	cash	completed	2026-02-20 22:54:43.251075		2026-02-20 22:54:43.251075	2026-02-20 22:54:43.251075
7	178	8271000	cash	completed	2026-02-20 23:01:35.703974		2026-02-20 23:01:35.703974	2026-02-20 23:01:35.703974
8	179	8271000	cash	completed	2026-02-20 23:07:39.406085		2026-02-20 23:07:39.406085	2026-02-20 23:07:39.406085
9	177	11028000	cash	completed	2026-02-20 23:11:26.258566		2026-02-20 23:11:26.258566	2026-02-20 23:11:26.258566
10	175	8100000	cash	completed	2026-02-20 23:11:45.336355		2026-02-20 23:11:45.336355	2026-02-20 23:11:45.336355
11	173	5699981	cash	completed	2026-02-20 23:11:59.149274		2026-02-20 23:11:59.149274	2026-02-20 23:11:59.149274
12	180	6930000	cash	completed	2026-02-20 23:14:58.885208		2026-02-20 23:14:58.885208	2026-02-20 23:14:58.885208
13	181	8100000	cash	completed	2026-02-20 23:33:21.406355		2026-02-20 23:33:21.406355	2026-02-20 23:33:21.406355
14	184	1800000	cash	completed	2026-02-20 23:41:48.004925		2026-02-20 23:41:48.004925	2026-02-20 23:41:48.004925
15	182	7360000	cash	completed	2026-02-20 23:47:25.588477		2026-02-20 23:47:25.588477	2026-02-20 23:47:25.588477
16	170	7650000	cash	completed	2026-02-20 23:48:30.181048		2026-02-20 23:48:30.181048	2026-02-20 23:48:30.181048
17	185	1999800	cash	completed	2026-03-01 23:26:58.817486		2026-03-01 23:26:58.817486	2026-03-01 23:26:58.817486
18	186	19998600	cash	completed	2026-03-02 12:36:06.083242		2026-03-02 12:36:06.083242	2026-03-02 12:36:06.083242
19	187	2996175	cash	completed	2026-04-12 23:39:03.475775		2026-04-12 23:39:03.475775	2026-04-12 23:39:03.475775
20	169	17100000	cash	completed	2026-04-12 23:39:07.357825		2026-04-12 23:39:07.357825	2026-04-12 23:39:07.357825
21	168	9975000	cash	completed	2026-04-12 23:39:10.308199		2026-04-12 23:39:10.308199	2026-04-12 23:39:10.308199
22	188	400000	cash	completed	2026-04-12 23:43:42.766075		2026-04-12 23:43:42.766075	2026-04-12 23:43:42.766075
23	189	9840000	cash	completed	2026-04-15 08:00:56.380555		2026-04-15 08:00:56.380555	2026-04-15 08:00:56.380555
24	166	19800000	cash	completed	2026-04-15 08:00:59.246649		2026-04-15 08:00:59.246649	2026-04-15 08:00:59.246649
25	165	2250000	cash	completed	2026-04-15 08:01:01.060329		2026-04-15 08:01:01.060329	2026-04-15 08:01:01.060329
\.


--
-- TOC entry 4048 (class 0 OID 16552)
-- Dependencies: 226
-- Data for Name: stock_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stock_history (history_id, item_id, old_status, new_status, changed_by, notes, created_at) FROM stdin;
3	6	unknown	sold	8	Order jual created	2026-01-16 11:16:36.881049
4	2	ready	sold	8	Order jual created	2026-01-17 22:06:01.847416
5	1	ready	sold	8	Order jual created	2026-01-17 22:06:47.316771
6	1	ready	sold	8	Order jual created	2026-01-17 22:24:59.738998
7	2	ready	sold	8	Order jual created	2026-01-17 22:33:00.617768
8	1	ready	sold	8	Order jual created	2026-01-17 22:42:54.120059
9	12	unknown	sold	6	Order jual created	2026-01-17 23:24:56.865533
10	1	ready	sold	8	Order jual created	2026-01-17 23:34:54.123517
11	14	ready	sold	6	Order jual created	2026-01-17 23:43:08.640752
14	2	ready	sold	8	Order jual created	2026-01-19 11:22:30.924903
15	2	ready	sold	8	Order jual created	2026-01-20 21:57:19.478087
16	1	ready	sold	8	Order jual created	2026-01-20 22:12:34.65289
17	1	ready	sold	8	Order jual created	2026-01-20 22:19:43.606554
18	1	ready	sold	8	Order jual created	2026-01-20 22:23:49.811491
19	1	ready	sold	8	Order jual created	2026-01-21 07:52:30.517428
20	16	unknown	sold	8	Order jual created	2026-01-21 07:59:59.742968
21	1	ready	sold	8	Order jual created	2026-01-21 08:20:40.620074
22	1	ready	sold	8	Order jual created	2026-01-21 08:21:53.096524
23	17	unknown	sold	8	Order jual created	2026-01-25 23:20:06.805285
24	18	unknown	sold	8	Order jual created	2026-02-08 09:56:10.542714
32	26	unknown	sold	8	Order jual created	2026-02-17 09:34:46.018916
33	27	unknown	sold	8	Order jual created	2026-02-17 09:38:17.205839
34	28	unknown	sold	6	Order jual created	2026-02-17 09:42:19.184346
35	29	unknown	sold	8	Order jual created	2026-02-17 09:43:24.559208
36	30	unknown	sold	6	Order jual created	2026-02-17 09:44:43.651122
37	31	unknown	sold	6	Order jual created	2026-02-17 09:45:06.28981
38	32	unknown	sold	8	Order jual created	2026-02-17 09:51:40.810068
39	33	unknown	sold	8	Order jual created	2026-02-19 21:50:23.403102
40	33	ready	sold	8	Order buyback created	2026-02-20 22:48:00.657843
41	34	unknown	sold	8	Order jual created	2026-02-20 22:54:29.624435
42	34	ready	sold	8	Order buyback created	2026-02-20 22:56:33.045432
43	35	unknown	sold	8	Order jual created	2026-02-20 23:01:09.97558
44	35	ready	sold	8	Order buyback created	2026-02-20 23:03:31.639921
45	36	unknown	sold	8	Order jual created	2026-02-20 23:14:36.932601
46	37	unknown	sold	8	Order jual created	2026-02-20 23:32:35.531882
47	38	unknown	sold	8	Order jual created	2026-02-20 23:35:45.188891
48	40	unknown	sold	8	Order jual created	2026-02-20 23:41:30.586535
49	41	unknown	sold	8	Order jual created	2026-03-01 23:26:27.147535
50	42	unknown	sold	8	Order jual created	2026-03-02 00:28:59.056714
51	43	unknown	sold	8	Order jual created	2026-03-05 23:05:30.311806
52	44	unknown	sold	8	Order jual created	2026-04-12 23:42:39.332876
53	45	unknown	sold	8	Order jual created	2026-04-12 23:47:08.025295
54	46	unknown	sold	23	Order jual created	2026-04-15 08:03:59.845593
\.


--
-- TOC entry 4058 (class 0 OID 16705)
-- Dependencies: 236
-- Data for Name: stock_mutations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stock_mutations (mutation_id, item_id, branch_id, type, quantity, previous_stock, current_stock, notes, reference_id, reference_type, created_by, created_at) FROM stdin;
\.


--
-- TOC entry 4056 (class 0 OID 16663)
-- Dependencies: 234
-- Data for Name: transfers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.transfers (transfer_id, from_branch_id, to_branch_id, item_name, quantity, notes, order_id, status, created_by, approved_by, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 4052 (class 0 OID 16612)
-- Dependencies: 230
-- Data for Name: uploaded_files; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.uploaded_files (id, filename, url, uploaded_at) FROM stdin;
1	1766990891540-955443125-scaled_91974ad7-9428-41b7-92dc-79be980e8f634719763601116113874.jpg	/uploads/1766990891540-955443125-scaled_91974ad7-9428-41b7-92dc-79be980e8f634719763601116113874.jpg	2025-12-29 13:48:11.569168
2	1766991555804-789006446-1766991540425_compressed.jpg	/uploads/1766991555804-789006446-1766991540425_compressed.jpg	2025-12-29 13:59:15.831962
3	1766996431085-547662435-1766996429405_compressed.jpg	/uploads/1766996431085-547662435-1766996429405_compressed.jpg	2025-12-29 15:20:31.10403
4	1766996514257-823297525-1766996512687_compressed.jpg	/uploads/1766996514257-823297525-1766996512687_compressed.jpg	2025-12-29 15:21:54.2687
5	1766997266038-683399551-1766997264249_compressed.jpg	/uploads/1766997266038-683399551-1766997264249_compressed.jpg	2025-12-29 15:34:26.060515
6	1766997559066-95568584-1766997557045_compressed.jpg	/uploads/1766997559066-95568584-1766997557045_compressed.jpg	2025-12-29 15:39:19.085064
7	1766998182542-352751485-1766998181056_compressed.jpg	/uploads/1766998182542-352751485-1766998181056_compressed.jpg	2025-12-29 15:49:42.575552
8	1766998579167-807505673-1766998577477_compressed.jpg	/uploads/1766998579167-807505673-1766998577477_compressed.jpg	2025-12-29 15:56:19.185175
9	1767231285591-847362577-scaled_d932ae0e-a112-4661-b513-931a61b0926c2307770621171499984_compressed.jpg	/uploads/1767231285591-847362577-scaled_d932ae0e-a112-4661-b513-931a61b0926c2307770621171499984_compressed.jpg	2026-01-01 08:34:45.63032
10	1767231401336-178211261-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767231401336-178211261-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:36:41.350113
11	1767231480113-603318266-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767231480113-603318266-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:38:00.131899
12	1767231503223-141171167-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767231503223-141171167-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:38:23.240015
13	1767231511661-145975185-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767231511661-145975185-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:38:31.666084
14	1767231576360-24233941-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767231576360-24233941-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:39:36.373173
15	1767231595554-433248198-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767231595554-433248198-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:39:55.578558
16	1767232024763-995392750-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767232024763-995392750-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:47:04.778806
17	1767232079739-882537060-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767232079739-882537060-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:47:59.816315
18	1767232130062-367968232-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767232130062-367968232-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:48:50.081831
19	1767232315787-228465262-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767232315787-228465262-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:51:55.806297
20	1767232794827-727038964-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767232794827-727038964-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 08:59:54.849875
21	1767232926586-95037531-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767232926586-95037531-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 09:02:06.6123
22	1767232989645-309491626-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767232989645-309491626-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 09:03:09.661953
23	1767233039691-730280033-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	/uploads/1767233039691-730280033-scaled_5f89f6a7-2a26-4226-b5b5-4b902f5266bf534074021774926877_compressed.jpg	2026-01-01 09:03:59.701891
24	1767234531894-506460721-scaled_9a15f258-7814-4ca2-8a3e-4f3550badc0e6904395878532500001_compressed.jpg	/uploads/1767234531894-506460721-scaled_9a15f258-7814-4ca2-8a3e-4f3550badc0e6904395878532500001_compressed.jpg	2026-01-01 09:28:51.916431
25	1767234616227-556790317-scaled_9a15f258-7814-4ca2-8a3e-4f3550badc0e6904395878532500001_compressed.jpg	/uploads/1767234616227-556790317-scaled_9a15f258-7814-4ca2-8a3e-4f3550badc0e6904395878532500001_compressed.jpg	2026-01-01 09:30:16.338677
26	1767234646408-908171404-scaled_9a15f258-7814-4ca2-8a3e-4f3550badc0e6904395878532500001_compressed.jpg	/uploads/1767234646408-908171404-scaled_9a15f258-7814-4ca2-8a3e-4f3550badc0e6904395878532500001_compressed.jpg	2026-01-01 09:30:46.426664
27	1767234825281-610012290-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767234825281-610012290-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:33:45.301568
28	1767234958484-402511129-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767234958484-402511129-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:35:58.510941
29	1767234964043-218974204-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767234964043-218974204-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:36:04.052692
30	1767234969688-176107817-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767234969688-176107817-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:36:09.692893
31	1767234974968-600040382-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767234974968-600040382-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:36:14.975573
32	1767234980208-410282238-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767234980208-410282238-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:36:20.212596
33	1767234985795-715043220-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767234985795-715043220-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:36:25.807867
34	1767234991660-727166103-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767234991660-727166103-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:36:31.664316
35	1767235024856-369727293-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767235024856-369727293-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:37:04.867638
36	1767235069161-566144282-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767235069161-566144282-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:37:49.167042
37	1767235074468-566997215-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767235074468-566997215-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:37:54.476802
38	1767235102338-743549198-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767235102338-743549198-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:38:22.352687
39	1767235368854-907532427-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767235368854-907532427-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:42:49.026485
40	1767235377768-681723114-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767235377768-681723114-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:42:57.790816
41	1767235552815-868233513-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767235552815-868233513-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:45:52.838095
42	1767235558101-97104956-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767235558101-97104956-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:45:58.10863
43	1767235563494-300505583-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767235563494-300505583-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:46:03.498233
44	1767235569937-134724076-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767235569937-134724076-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 09:46:09.943749
45	1767236586234-25327374-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	/uploads/1767236586234-25327374-scaled_468f0fab-37e0-46c2-9f52-bd3c8b788b0a6361791443903982311_compressed.jpg	2026-01-01 10:03:06.28415
46	1767236644705-755590665-scaled_c6c33cf2-7ef3-423c-9fa4-7bbf9b38027c421167684337101818_compressed.jpg	/uploads/1767236644705-755590665-scaled_c6c33cf2-7ef3-423c-9fa4-7bbf9b38027c421167684337101818_compressed.jpg	2026-01-01 10:04:04.725618
47	1767236650264-325402687-scaled_c6c33cf2-7ef3-423c-9fa4-7bbf9b38027c421167684337101818_compressed.jpg	/uploads/1767236650264-325402687-scaled_c6c33cf2-7ef3-423c-9fa4-7bbf9b38027c421167684337101818_compressed.jpg	2026-01-01 10:04:10.277923
48	1767236655682-752450385-scaled_c6c33cf2-7ef3-423c-9fa4-7bbf9b38027c421167684337101818_compressed.jpg	/uploads/1767236655682-752450385-scaled_c6c33cf2-7ef3-423c-9fa4-7bbf9b38027c421167684337101818_compressed.jpg	2026-01-01 10:04:15.704923
49	1767236661453-870303071-scaled_c6c33cf2-7ef3-423c-9fa4-7bbf9b38027c421167684337101818_compressed.jpg	/uploads/1767236661453-870303071-scaled_c6c33cf2-7ef3-423c-9fa4-7bbf9b38027c421167684337101818_compressed.jpg	2026-01-01 10:04:21.465514
50	1767236667507-455416729-scaled_c6c33cf2-7ef3-423c-9fa4-7bbf9b38027c421167684337101818_compressed.jpg	/uploads/1767236667507-455416729-scaled_c6c33cf2-7ef3-423c-9fa4-7bbf9b38027c421167684337101818_compressed.jpg	2026-01-01 10:04:27.511668
51	1767237084087-449958068-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237084087-449958068-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:11:24.111237
52	1767237090844-884126413-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237090844-884126413-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:11:30.854947
53	1767237119944-833995613-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237119944-833995613-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:11:59.963844
54	1767237141851-746437732-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237141851-746437732-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:12:21.864435
55	1767237801588-810734230-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237801588-810734230-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:23:21.609642
56	1767237807189-681713565-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237807189-681713565-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:23:27.220908
57	1767237814060-124447405-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237814060-124447405-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:23:34.075513
58	1767237917390-422723754-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237917390-422723754-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:25:17.424334
59	1767237923806-935505344-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237923806-935505344-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:25:23.822305
60	1767237929123-196652853-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237929123-196652853-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:25:29.128155
61	1767237964328-383324831-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237964328-383324831-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:26:04.342286
62	1767237969670-421000628-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767237969670-421000628-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:26:09.673837
63	1767238006603-148803256-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767238006603-148803256-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:26:46.619167
64	1767238012134-378999850-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767238012134-378999850-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:26:52.138389
65	1767238535209-876141268-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767238535209-876141268-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:35:35.235828
66	1767238540716-995940149-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	/uploads/1767238540716-995940149-scaled_ddc3edfd-50d8-4bc2-89d7-cc92b9d4a10b7787563634859192538_compressed.jpg	2026-01-01 10:35:40.724821
67	1767238584610-449544362-scaled_e1a71668-d7b0-444a-9a52-fcdf696390cb80496424132294368_compressed.jpg	/uploads/1767238584610-449544362-scaled_e1a71668-d7b0-444a-9a52-fcdf696390cb80496424132294368_compressed.jpg	2026-01-01 10:36:24.634083
68	1767238590183-163472967-scaled_e1a71668-d7b0-444a-9a52-fcdf696390cb80496424132294368_compressed.jpg	/uploads/1767238590183-163472967-scaled_e1a71668-d7b0-444a-9a52-fcdf696390cb80496424132294368_compressed.jpg	2026-01-01 10:36:30.187082
69	1767238595738-861620727-scaled_e1a71668-d7b0-444a-9a52-fcdf696390cb80496424132294368_compressed.jpg	/uploads/1767238595738-861620727-scaled_e1a71668-d7b0-444a-9a52-fcdf696390cb80496424132294368_compressed.jpg	2026-01-01 10:36:35.744405
70	1767238947037-667487308-scaled_e1a71668-d7b0-444a-9a52-fcdf696390cb80496424132294368_compressed.jpg	/uploads/1767238947037-667487308-scaled_e1a71668-d7b0-444a-9a52-fcdf696390cb80496424132294368_compressed.jpg	2026-01-01 10:42:27.07006
71	1767238983099-862326701-scaled_e1a71668-d7b0-444a-9a52-fcdf696390cb80496424132294368_compressed.jpg	/uploads/1767238983099-862326701-scaled_e1a71668-d7b0-444a-9a52-fcdf696390cb80496424132294368_compressed.jpg	2026-01-01 10:43:03.115151
72	1767239873019-685380025-scaled_20b54f78-3ff1-40ae-9d40-d04f30c1adbd4332031332415476398_compressed.jpg	/uploads/1767239873019-685380025-scaled_20b54f78-3ff1-40ae-9d40-d04f30c1adbd4332031332415476398_compressed.jpg	2026-01-01 10:57:53.043779
73	1767240114317-964027275-scaled_31f704ea-05f3-454d-a257-089d5f853afa7122938016470599242_compressed.jpg	/uploads/1767240114317-964027275-scaled_31f704ea-05f3-454d-a257-089d5f853afa7122938016470599242_compressed.jpg	2026-01-01 11:01:54.347043
74	1767240293838-423226143-scaled_a64774ba-768f-4af0-a663-80d2f2c302718806198294859809375_compressed.jpg	/uploads/1767240293838-423226143-scaled_a64774ba-768f-4af0-a663-80d2f2c302718806198294859809375_compressed.jpg	2026-01-01 11:04:53.925251
75	1767240427771-117010776-scaled_a64774ba-768f-4af0-a663-80d2f2c302718806198294859809375_compressed.jpg	/uploads/1767240427771-117010776-scaled_a64774ba-768f-4af0-a663-80d2f2c302718806198294859809375_compressed.jpg	2026-01-01 11:07:07.789262
76	1767242122839-622565947-scaled_ac197207-9d30-4726-935d-ee748639ec297921762305480625101_compressed.jpg	/uploads/1767242122839-622565947-scaled_ac197207-9d30-4726-935d-ee748639ec297921762305480625101_compressed.jpg	2026-01-01 11:35:22.888047
77	1767245954341-303858975-scaled_710c0b54-d559-4f80-bea4-def8f29693401923482409093928838_compressed.jpg	/uploads/1767245954341-303858975-scaled_710c0b54-d559-4f80-bea4-def8f29693401923482409093928838_compressed.jpg	2026-01-01 12:39:14.368406
78	1767281939774-799425258-scaled_25baec62-c6ad-46ed-ab27-6679423dc7406705549899172526115_compressed.jpg	/uploads/1767281939774-799425258-scaled_25baec62-c6ad-46ed-ab27-6679423dc7406705549899172526115_compressed.jpg	2026-01-01 22:38:59.949567
79	1767281945747-783602391-scaled_25baec62-c6ad-46ed-ab27-6679423dc7406705549899172526115_compressed.jpg	/uploads/1767281945747-783602391-scaled_25baec62-c6ad-46ed-ab27-6679423dc7406705549899172526115_compressed.jpg	2026-01-01 22:39:05.793326
80	1767282251458-503087463-scaled_25baec62-c6ad-46ed-ab27-6679423dc7406705549899172526115_compressed.jpg	/uploads/1767282251458-503087463-scaled_25baec62-c6ad-46ed-ab27-6679423dc7406705549899172526115_compressed.jpg	2026-01-01 22:44:11.490567
81	1767282374122-694672701-scaled_5f71e49d-6dd0-4a54-b782-d066383bf9841998667620387944430_compressed.jpg	/uploads/1767282374122-694672701-scaled_5f71e49d-6dd0-4a54-b782-d066383bf9841998667620387944430_compressed.jpg	2026-01-01 22:46:14.170038
82	1767282380890-877786615-scaled_5f71e49d-6dd0-4a54-b782-d066383bf9841998667620387944430_compressed.jpg	/uploads/1767282380890-877786615-scaled_5f71e49d-6dd0-4a54-b782-d066383bf9841998667620387944430_compressed.jpg	2026-01-01 22:46:20.909198
83	1767282413108-57636902-scaled_5f71e49d-6dd0-4a54-b782-d066383bf9841998667620387944430_compressed.jpg	/uploads/1767282413108-57636902-scaled_5f71e49d-6dd0-4a54-b782-d066383bf9841998667620387944430_compressed.jpg	2026-01-01 22:46:53.132558
84	1767283060812-90331075-scaled_5f71e49d-6dd0-4a54-b782-d066383bf9841998667620387944430_compressed.jpg	/uploads/1767283060812-90331075-scaled_5f71e49d-6dd0-4a54-b782-d066383bf9841998667620387944430_compressed.jpg	2026-01-01 22:57:40.876428
85	1767283161688-53209076-scaled_62f55f23-5e58-42b5-9d45-52ecd45080d25340491940092633201_compressed.jpg	/uploads/1767283161688-53209076-scaled_62f55f23-5e58-42b5-9d45-52ecd45080d25340491940092633201_compressed.jpg	2026-01-01 22:59:21.805561
86	1767283170706-567630952-scaled_62f55f23-5e58-42b5-9d45-52ecd45080d25340491940092633201_compressed.jpg	/uploads/1767283170706-567630952-scaled_62f55f23-5e58-42b5-9d45-52ecd45080d25340491940092633201_compressed.jpg	2026-01-01 22:59:30.727749
87	1767283183300-549454577-scaled_62f55f23-5e58-42b5-9d45-52ecd45080d25340491940092633201_compressed.jpg	/uploads/1767283183300-549454577-scaled_62f55f23-5e58-42b5-9d45-52ecd45080d25340491940092633201_compressed.jpg	2026-01-01 22:59:43.328429
88	1767283384392-492995905-scaled_62f55f23-5e58-42b5-9d45-52ecd45080d25340491940092633201_compressed.jpg	/uploads/1767283384392-492995905-scaled_62f55f23-5e58-42b5-9d45-52ecd45080d25340491940092633201_compressed.jpg	2026-01-01 23:03:04.45089
89	1767283485614-499402589-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	/uploads/1767283485614-499402589-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	2026-01-01 23:04:45.672697
90	1767283493160-332101385-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	/uploads/1767283493160-332101385-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	2026-01-01 23:04:53.190865
91	1767283502249-353791885-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	/uploads/1767283502249-353791885-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	2026-01-01 23:05:02.282969
92	1767283852789-142514607-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	/uploads/1767283852789-142514607-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	2026-01-01 23:10:52.822079
93	1767283902515-371324913-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	/uploads/1767283902515-371324913-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	2026-01-01 23:11:42.54675
94	1767283908129-815868458-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	/uploads/1767283908129-815868458-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	2026-01-01 23:11:48.135103
95	1767283953123-384770623-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	/uploads/1767283953123-384770623-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	2026-01-01 23:12:33.138451
96	1767283958491-791852054-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	/uploads/1767283958491-791852054-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	2026-01-01 23:12:38.518497
97	1767283980774-360601777-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	/uploads/1767283980774-360601777-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	2026-01-01 23:13:00.816993
98	1767284180997-534466042-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	/uploads/1767284180997-534466042-scaled_73d1fb8e-be5c-4733-829e-1766e40996fb8041785923783236521_compressed.jpg	2026-01-01 23:16:21.074258
99	1767303479701-697916071-scaled_0a8b649e-1298-415c-b05a-7d7c749120af6254716184563510006_compressed.jpg	/uploads/1767303479701-697916071-scaled_0a8b649e-1298-415c-b05a-7d7c749120af6254716184563510006_compressed.jpg	2026-01-02 04:37:59.72361
100	1767715059085-42328929-scaled_84f02aa6-d280-4148-a12e-0d9a387c55ec1672355256812221889_compressed.jpg	/uploads/1767715059085-42328929-scaled_84f02aa6-d280-4148-a12e-0d9a387c55ec1672355256812221889_compressed.jpg	2026-01-06 22:57:39.110849
101	1767716047615-52736741-scaled_c4639314-9f29-435f-abc3-472ab7b9e3391478925383286787097_compressed.jpg	/uploads/1767716047615-52736741-scaled_c4639314-9f29-435f-abc3-472ab7b9e3391478925383286787097_compressed.jpg	2026-01-06 23:14:07.639011
102	1767722012048-273442850-scaled_510544dc-40b0-48c4-9671-b65b877dafd52564916653000494329_compressed.jpg	/uploads/1767722012048-273442850-scaled_510544dc-40b0-48c4-9671-b65b877dafd52564916653000494329_compressed.jpg	2026-01-07 00:53:32.16681
103	1767769945457-121397032-null	/uploads/1767769945457-121397032-null	2026-01-07 14:12:25.468024
104	1767769950734-280095424-null	/uploads/1767769950734-280095424-null	2026-01-07 14:12:30.735224
105	1767770102774-433584477-scaled_adc55296-0610-4ba2-8347-890df056fd825832069565579071168_compressed.jpg	/uploads/1767770102774-433584477-scaled_adc55296-0610-4ba2-8347-890df056fd825832069565579071168_compressed.jpg	2026-01-07 14:15:02.793221
106	1768668941652-269044854-test_order.json	/uploads/1768668941652-269044854-test_order.json	2026-01-17 23:55:41.666427
107	1768669013615-321172083-test_order.json	/uploads/1768669013615-321172083-test_order.json	2026-01-17 23:56:53.620584
108	1768669061013-481409720-test_order.json	/uploads/1768669061013-481409720-test_order.json	2026-01-17 23:57:41.01979
109	1768921516605-697144646-test_upload.txt	/uploads/1768921516605-697144646-test_upload.txt	2026-01-20 22:05:16.617631
110	1768921652791-300097553-test_upload.txt	/uploads/1768921652791-300097553-test_upload.txt	2026-01-20 22:07:32.797545
111	1768921837868-207655405-test_upload.txt	/uploads/1768921837868-207655405-test_upload.txt	2026-01-20 22:10:37.873664
112	1768922297952-291381979-test_upload.txt	/uploads/1768922297952-291381979-test_upload.txt	2026-01-20 22:18:17.962155
113	1768922383568-921474883-b748a47a-0405-4623-99e7-ef2fd021aaf04200780978984882608_compressed.jpg	/uploads/1768922383568-921474883-b748a47a-0405-4623-99e7-ef2fd021aaf04200780978984882608_compressed.jpg	2026-01-20 22:19:43.58022
114	1768922629736-783957173-f7613990-eaca-4b0d-9a61-0c9d7332e4701320074594975920304_compressed.jpg	/uploads/1768922629736-783957173-f7613990-eaca-4b0d-9a61-0c9d7332e4701320074594975920304_compressed.jpg	2026-01-20 22:23:49.769816
115	1768922803704-823412650-test_upload.txt	/uploads/1768922803704-823412650-test_upload.txt	2026-01-20 22:26:43.713025
116	1768956750348-821484540-1e2fdbf2-5ce6-4a3a-b227-62b7ddafbce87898600706979287436_compressed.jpg	/uploads/1768956750348-821484540-1e2fdbf2-5ce6-4a3a-b227-62b7ddafbce87898600706979287436_compressed.jpg	2026-01-21 07:52:30.390324
117	1768958440452-411795189-e8526d3d-57db-4591-8b15-01fbe6fed1a2633054209766810505_compressed.jpg	/uploads/1768958440452-411795189-e8526d3d-57db-4591-8b15-01fbe6fed1a2633054209766810505_compressed.jpg	2026-01-21 08:20:40.51732
118	1768958513036-680620799-7f312017-1b7f-4c9c-9701-4e55d5768f0b91788507395030061_compressed.jpg	/uploads/1768958513036-680620799-7f312017-1b7f-4c9c-9701-4e55d5768f0b91788507395030061_compressed.jpg	2026-01-21 08:21:53.056366
119	1769358006671-299120019-4a86c6b7-4bcd-48b3-9293-9da4bdee50b12713237126349160429_compressed.jpg	/uploads/1769358006671-299120019-4a86c6b7-4bcd-48b3-9293-9da4bdee50b12713237126349160429_compressed.jpg	2026-01-25 23:20:06.703749
120	1770341928802-839680275-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	/uploads/1770341928802-839680275-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	2026-02-06 08:38:48.834014
121	1770341941813-516828715-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	/uploads/1770341941813-516828715-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	2026-02-06 08:39:01.847063
122	1770341950548-819721641-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	/uploads/1770341950548-819721641-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	2026-02-06 08:39:10.569364
123	1770341969700-438162344-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	/uploads/1770341969700-438162344-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	2026-02-06 08:39:29.739106
124	1770341976840-686093933-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	/uploads/1770341976840-686093933-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	2026-02-06 08:39:36.849751
125	1770341989565-831768637-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	/uploads/1770341989565-831768637-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	2026-02-06 08:39:49.592618
126	1770342002032-140119594-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	/uploads/1770342002032-140119594-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	2026-02-06 08:40:02.045449
127	1770342007705-758058215-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	/uploads/1770342007705-758058215-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	2026-02-06 08:40:07.716928
128	1770342130830-934338338-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	/uploads/1770342130830-934338338-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	2026-02-06 08:42:10.861103
129	1770342144768-651987260-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	/uploads/1770342144768-651987260-42b1882a-4f71-4eb7-a2e8-bbee5d865b342817257793514467912_compressed.jpg	2026-02-06 08:42:24.79524
130	1770342249079-547928425-063d6607-b020-44c0-b7cc-42eabcd0bd813725929025526224762_compressed.jpg	/uploads/1770342249079-547928425-063d6607-b020-44c0-b7cc-42eabcd0bd813725929025526224762_compressed.jpg	2026-02-06 08:44:09.110395
131	1770342274539-678070370-063d6607-b020-44c0-b7cc-42eabcd0bd813725929025526224762_compressed.jpg	/uploads/1770342274539-678070370-063d6607-b020-44c0-b7cc-42eabcd0bd813725929025526224762_compressed.jpg	2026-02-06 08:44:34.555227
132	1770519370405-967780451-8bf077d8-396a-4ef1-a34d-53b5490b47b31280709800342521887_compressed.jpg	/uploads/1770519370405-967780451-8bf077d8-396a-4ef1-a34d-53b5490b47b31280709800342521887_compressed.jpg	2026-02-08 09:56:10.441873
133	1771295444870-879809100-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	/uploads/1771295444870-879809100-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	2026-02-17 09:30:44.966799
134	1771295451103-985335977-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	/uploads/1771295451103-985335977-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	2026-02-17 09:30:51.143444
135	1771295458224-868431182-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	/uploads/1771295458224-868431182-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	2026-02-17 09:30:58.245354
136	1771295497642-916361187-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	/uploads/1771295497642-916361187-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	2026-02-17 09:31:37.674669
137	1771295545784-216639044-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	/uploads/1771295545784-216639044-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	2026-02-17 09:32:25.823358
138	1771295553735-352864567-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	/uploads/1771295553735-352864567-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	2026-02-17 09:32:33.763905
139	1771295567240-202543422-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	/uploads/1771295567240-202543422-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	2026-02-17 09:32:47.27314
140	1771295685921-313339141-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	/uploads/1771295685921-313339141-88f1671c-2c0f-475c-8d85-8a6e12db2c322871745705533642954_compressed.jpg	2026-02-17 09:34:45.969398
141	1771295897126-678923464-08cfad73-9863-4168-baa5-63de6deee7e45483954934886774672_compressed.jpg	/uploads/1771295897126-678923464-08cfad73-9863-4168-baa5-63de6deee7e45483954934886774672_compressed.jpg	2026-02-17 09:38:17.157489
142	1771296204509-356756407-605128b8-55f4-4c2f-a7e1-7da0252d2ea38113452595898263251_compressed.jpg	/uploads/1771296204509-356756407-605128b8-55f4-4c2f-a7e1-7da0252d2ea38113452595898263251_compressed.jpg	2026-02-17 09:43:24.532239
143	1771296700752-14272089-78fca1eb-edbc-403e-91ed-d1cd928c2d785574261746705918610_compressed.jpg	/uploads/1771296700752-14272089-78fca1eb-edbc-403e-91ed-d1cd928c2d785574261746705918610_compressed.jpg	2026-02-17 09:51:40.766535
144	1771512623293-669832820-cf61bbaa-e04d-4277-9b5a-65ff446c79f22224684779849167315_compressed.jpg	/uploads/1771512623293-669832820-cf61bbaa-e04d-4277-9b5a-65ff446c79f22224684779849167315_compressed.jpg	2026-02-19 21:50:23.328046
145	1771602869460-603541159-64635c0f-2375-40ee-9587-4b63b78bc8486880528635135730139_compressed.jpg	/uploads/1771602869460-603541159-64635c0f-2375-40ee-9587-4b63b78bc8486880528635135730139_compressed.jpg	2026-02-20 22:54:29.519259
146	1771603269854-785206434-2072a978-23f2-452f-8784-95d4e605fd0a2853489103302423153_compressed.jpg	/uploads/1771603269854-785206434-2072a978-23f2-452f-8784-95d4e605fd0a2853489103302423153_compressed.jpg	2026-02-20 23:01:09.888914
147	1771604076738-438334243-d0bda1c3-ec4a-4317-bc1b-a8593ba118d34667942638837181606_compressed.jpg	/uploads/1771604076738-438334243-d0bda1c3-ec4a-4317-bc1b-a8593ba118d34667942638837181606_compressed.jpg	2026-02-20 23:14:36.867552
148	1771605155413-194319237-b57d591b-c1de-4fc5-a269-1560eb7520f14573410742959882402_compressed.jpg	/uploads/1771605155413-194319237-b57d591b-c1de-4fc5-a269-1560eb7520f14573410742959882402_compressed.jpg	2026-02-20 23:32:35.441739
149	1771605345098-972244640-0ef04193-82c7-4864-952f-8a3797df7faa2999963801905726293_compressed.jpg	/uploads/1771605345098-972244640-0ef04193-82c7-4864-952f-8a3797df7faa2999963801905726293_compressed.jpg	2026-02-20 23:35:45.126853
150	1771605536389-124538879-0ef04193-82c7-4864-952f-8a3797df7faa2999963801905726293_compressed.jpg	/uploads/1771605536389-124538879-0ef04193-82c7-4864-952f-8a3797df7faa2999963801905726293_compressed.jpg	2026-02-20 23:38:56.411669
151	1771605690531-417487211-6f2b38e4-1421-4bb8-b33c-7d89c40329e37362949465524025492_compressed.jpg	/uploads/1771605690531-417487211-6f2b38e4-1421-4bb8-b33c-7d89c40329e37362949465524025492_compressed.jpg	2026-02-20 23:41:30.553679
152	1772382387022-982052689-e4f0cb52-cc23-4833-a55b-8fd7f264447e2817965383034992375_compressed.jpg	/uploads/1772382387022-982052689-e4f0cb52-cc23-4833-a55b-8fd7f264447e2817965383034992375_compressed.jpg	2026-03-01 23:26:27.037722
\.


--
-- TOC entry 4042 (class 0 OID 16495)
-- Dependencies: 220
-- Data for Name: user_branch_roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_branch_roles (id, user_id, branch_id, role, is_primary) FROM stdin;
3	8	1	cs	f
4	8	1	kasir	f
5	8	2	cs	f
9	8	1	admin_toko	f
10	8	1	superadmin	f
11	8	2	kasir	f
16	8	4	cs	f
17	8	3	admin_workshop	t
18	8	3	tukang	f
19	23	4	superadmin	f
21	23	1	admin_toko	t
22	23	1	kasir	f
23	23	1	cs	f
\.


--
-- TOC entry 4038 (class 0 OID 16469)
-- Dependencies: 216
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (user_id, username, password_hash, status, created_at, updated_at) FROM stdin;
6	admin@email.com	b03ddf3ca2e714a6548e7495e2a03f5e824eaac9837cd7f159c67b90fb4b7342	aktif	2025-12-26 22:43:05.465959	2025-12-26 22:43:05.465959
11	admin	ef92b778bafe771e89245b89ecbc08a44a4e166c06659911881f383d4473e94f	active	2026-01-04 15:13:25.270385	2026-01-04 15:13:25.270385
8	customer_service	$2b$10$Xs/PKzLTc0StoIWNFaaeHe0MO8e03a4nTcuwQQXbW8RUzJdOyUYo6	active	2025-12-27 07:51:35.373503	2026-04-14 21:11:28.622685
23	superadmin	$2b$10$0sv/ZDjJ.jFxScmt6Yzaae.rGFbJ4JfSg7knDmhuQ4p2Edk02lDL.	active	2026-04-14 21:06:40.248632	2026-04-14 21:12:55.594443
\.


--
-- TOC entry 4084 (class 0 OID 0)
-- Dependencies: 217
-- Name: branches_branch_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.branches_branch_id_seq', 19, true);


--
-- TOC entry 4085 (class 0 OID 0)
-- Dependencies: 227
-- Name: customers_customer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_customer_id_seq', 18, true);


--
-- TOC entry 4086 (class 0 OID 0)
-- Dependencies: 238
-- Name: item_conditions_condition_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.item_conditions_condition_id_seq', 1, false);


--
-- TOC entry 4087 (class 0 OID 0)
-- Dependencies: 221
-- Name: items_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.items_item_id_seq', 46, true);


--
-- TOC entry 4088 (class 0 OID 0)
-- Dependencies: 240
-- Name: order_items_order_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_items_order_item_id_seq', 27, true);


--
-- TOC entry 4089 (class 0 OID 0)
-- Dependencies: 237
-- Name: order_nota_seq; Type: SEQUENCE SET; Schema: public; Owner: macbookpro2019
--

SELECT pg_catalog.setval('public.order_nota_seq', 14, true);


--
-- TOC entry 4090 (class 0 OID 0)
-- Dependencies: 223
-- Name: orders_order_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_order_id_seq', 190, true);


--
-- TOC entry 4091 (class 0 OID 0)
-- Dependencies: 231
-- Name: payments_payment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.payments_payment_id_seq', 25, true);


--
-- TOC entry 4092 (class 0 OID 0)
-- Dependencies: 225
-- Name: stock_history_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stock_history_history_id_seq', 54, true);


--
-- TOC entry 4093 (class 0 OID 0)
-- Dependencies: 235
-- Name: stock_mutations_mutation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stock_mutations_mutation_id_seq', 1, false);


--
-- TOC entry 4094 (class 0 OID 0)
-- Dependencies: 233
-- Name: transfers_transfer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.transfers_transfer_id_seq', 1, false);


--
-- TOC entry 4095 (class 0 OID 0)
-- Dependencies: 229
-- Name: uploaded_files_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.uploaded_files_id_seq', 152, true);


--
-- TOC entry 4096 (class 0 OID 0)
-- Dependencies: 219
-- Name: user_branch_roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_branch_roles_id_seq', 23, true);


--
-- TOC entry 4097 (class 0 OID 0)
-- Dependencies: 215
-- Name: users_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_user_id_seq', 25, true);


--
-- TOC entry 3806 (class 2606 OID 16493)
-- Name: branches branches_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_code_key UNIQUE (code);


--
-- TOC entry 3808 (class 2606 OID 16491)
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (branch_id);


--
-- TOC entry 3838 (class 2606 OID 16586)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);


--
-- TOC entry 3866 (class 2606 OID 25036)
-- Name: item_conditions item_conditions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_conditions
    ADD CONSTRAINT item_conditions_pkey PRIMARY KEY (condition_id);


--
-- TOC entry 3823 (class 2606 OID 16737)
-- Name: items items_kode_produk_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_kode_produk_key UNIQUE (kode_produk);


--
-- TOC entry 3825 (class 2606 OID 16524)
-- Name: items items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (item_id);


--
-- TOC entry 3827 (class 2606 OID 24965)
-- Name: items items_qr_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_qr_code_key UNIQUE (qr_code);


--
-- TOC entry 3869 (class 2606 OID 25071)
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (order_item_id);


--
-- TOC entry 3834 (class 2606 OID 16540)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (order_id);


--
-- TOC entry 3848 (class 2606 OID 16652)
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (payment_id);


--
-- TOC entry 3836 (class 2606 OID 16560)
-- Name: stock_history stock_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_history
    ADD CONSTRAINT stock_history_pkey PRIMARY KEY (history_id);


--
-- TOC entry 3860 (class 2606 OID 16714)
-- Name: stock_mutations stock_mutations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_mutations
    ADD CONSTRAINT stock_mutations_pkey PRIMARY KEY (mutation_id);


--
-- TOC entry 3854 (class 2606 OID 16674)
-- Name: transfers transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_pkey PRIMARY KEY (transfer_id);


--
-- TOC entry 3842 (class 2606 OID 16620)
-- Name: uploaded_files uploaded_files_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uploaded_files
    ADD CONSTRAINT uploaded_files_pkey PRIMARY KEY (id);


--
-- TOC entry 3815 (class 2606 OID 16503)
-- Name: user_branch_roles user_branch_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_branch_roles
    ADD CONSTRAINT user_branch_roles_pkey PRIMARY KEY (id);


--
-- TOC entry 3802 (class 2606 OID 16478)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- TOC entry 3804 (class 2606 OID 16480)
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- TOC entry 3809 (class 1259 OID 24946)
-- Name: idx_branches_initials; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_branches_initials ON public.branches USING btree (initials);


--
-- TOC entry 3810 (class 1259 OID 24945)
-- Name: idx_branches_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_branches_name ON public.branches USING btree (name);


--
-- TOC entry 3839 (class 1259 OID 24955)
-- Name: idx_customers_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_name ON public.customers USING btree (name);


--
-- TOC entry 3840 (class 1259 OID 24954)
-- Name: idx_customers_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_phone ON public.customers USING btree (phone);


--
-- TOC entry 3861 (class 1259 OID 25057)
-- Name: idx_item_conditions_dinilai_oleh; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_item_conditions_dinilai_oleh ON public.item_conditions USING btree (dinilai_oleh);


--
-- TOC entry 3862 (class 1259 OID 25052)
-- Name: idx_item_conditions_item_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_item_conditions_item_id ON public.item_conditions USING btree (item_id);


--
-- TOC entry 3863 (class 1259 OID 25054)
-- Name: idx_item_conditions_kondisi_fisik; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_item_conditions_kondisi_fisik ON public.item_conditions USING btree (kondisi_fisik);


--
-- TOC entry 3864 (class 1259 OID 25053)
-- Name: idx_item_conditions_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_item_conditions_order_id ON public.item_conditions USING btree (order_id);


--
-- TOC entry 3816 (class 1259 OID 24951)
-- Name: idx_items_branch_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_branch_id ON public.items USING btree (branch_id);


--
-- TOC entry 3817 (class 1259 OID 24953)
-- Name: idx_items_kategori; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_kategori ON public.items USING btree (kategori);


--
-- TOC entry 3818 (class 1259 OID 25018)
-- Name: idx_items_ownership; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_ownership ON public.items USING btree (ownership);


--
-- TOC entry 3819 (class 1259 OID 25021)
-- Name: idx_items_qr_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_qr_code ON public.items USING btree (qr_code);


--
-- TOC entry 3820 (class 1259 OID 24952)
-- Name: idx_items_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_status ON public.items USING btree (status);


--
-- TOC entry 3821 (class 1259 OID 25019)
-- Name: idx_items_stock_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_stock_type ON public.items USING btree (stock_type);


--
-- TOC entry 3867 (class 1259 OID 25082)
-- Name: idx_order_items_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_order_id ON public.order_items USING btree (order_id);


--
-- TOC entry 3828 (class 1259 OID 24956)
-- Name: idx_orders_branch_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_branch_id ON public.orders USING btree (branch_id);


--
-- TOC entry 3829 (class 1259 OID 24958)
-- Name: idx_orders_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_customer_id ON public.orders USING btree (customer_id);


--
-- TOC entry 3830 (class 1259 OID 24959)
-- Name: idx_orders_order_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_order_number ON public.orders USING btree (order_number);


--
-- TOC entry 3831 (class 1259 OID 24988)
-- Name: idx_orders_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_status ON public.orders USING btree (status);


--
-- TOC entry 3832 (class 1259 OID 24957)
-- Name: idx_orders_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_user_id ON public.orders USING btree (user_id);


--
-- TOC entry 3843 (class 1259 OID 16661)
-- Name: idx_payments_method; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_method ON public.payments USING btree (method);


--
-- TOC entry 3844 (class 1259 OID 16658)
-- Name: idx_payments_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_order_id ON public.payments USING btree (order_id);


--
-- TOC entry 3845 (class 1259 OID 24962)
-- Name: idx_payments_payment_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_payment_date ON public.payments USING btree (payment_date);


--
-- TOC entry 3846 (class 1259 OID 16659)
-- Name: idx_payments_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_status ON public.payments USING btree (status);


--
-- TOC entry 3855 (class 1259 OID 16731)
-- Name: idx_stock_mutations_branch_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_stock_mutations_branch_id ON public.stock_mutations USING btree (branch_id);


--
-- TOC entry 3856 (class 1259 OID 16733)
-- Name: idx_stock_mutations_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_stock_mutations_created_at ON public.stock_mutations USING btree (created_at);


--
-- TOC entry 3857 (class 1259 OID 16730)
-- Name: idx_stock_mutations_item_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_stock_mutations_item_id ON public.stock_mutations USING btree (item_id);


--
-- TOC entry 3858 (class 1259 OID 16732)
-- Name: idx_stock_mutations_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_stock_mutations_type ON public.stock_mutations USING btree (type);


--
-- TOC entry 3849 (class 1259 OID 16703)
-- Name: idx_transfers_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_created_at ON public.transfers USING btree (created_at);


--
-- TOC entry 3850 (class 1259 OID 16700)
-- Name: idx_transfers_from_branch; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_from_branch ON public.transfers USING btree (from_branch_id);


--
-- TOC entry 3851 (class 1259 OID 16702)
-- Name: idx_transfers_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_status ON public.transfers USING btree (status);


--
-- TOC entry 3852 (class 1259 OID 16701)
-- Name: idx_transfers_to_branch; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_to_branch ON public.transfers USING btree (to_branch_id);


--
-- TOC entry 3811 (class 1259 OID 24949)
-- Name: idx_user_branch_roles_branch_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_branch_roles_branch_id ON public.user_branch_roles USING btree (branch_id);


--
-- TOC entry 3812 (class 1259 OID 24950)
-- Name: idx_user_branch_roles_role; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_branch_roles_role ON public.user_branch_roles USING btree (role);


--
-- TOC entry 3813 (class 1259 OID 24948)
-- Name: idx_user_branch_roles_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_branch_roles_user_id ON public.user_branch_roles USING btree (user_id);


--
-- TOC entry 3800 (class 1259 OID 24947)
-- Name: idx_users_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_status ON public.users USING btree (status);


--
-- TOC entry 3893 (class 2620 OID 25056)
-- Name: item_conditions trigger_update_item_conditions_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_item_conditions_updated_at BEFORE UPDATE ON public.item_conditions FOR EACH ROW EXECUTE FUNCTION public.update_item_conditions_updated_at();


--
-- TOC entry 3878 (class 2606 OID 24939)
-- Name: customers customers_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(branch_id);


--
-- TOC entry 3873 (class 2606 OID 16622)
-- Name: orders fk_orders_customers; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_orders_customers FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id);


--
-- TOC entry 3888 (class 2606 OID 25047)
-- Name: item_conditions item_conditions_dinilai_oleh_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_conditions
    ADD CONSTRAINT item_conditions_dinilai_oleh_fkey FOREIGN KEY (dinilai_oleh) REFERENCES public.users(user_id);


--
-- TOC entry 3889 (class 2606 OID 25037)
-- Name: item_conditions item_conditions_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_conditions
    ADD CONSTRAINT item_conditions_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id) ON DELETE CASCADE;


--
-- TOC entry 3890 (class 2606 OID 25042)
-- Name: item_conditions item_conditions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_conditions
    ADD CONSTRAINT item_conditions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE CASCADE;


--
-- TOC entry 3872 (class 2606 OID 16525)
-- Name: items items_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(branch_id);


--
-- TOC entry 3891 (class 2606 OID 25077)
-- Name: order_items order_items_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id);


--
-- TOC entry 3892 (class 2606 OID 25072)
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE CASCADE;


--
-- TOC entry 3874 (class 2606 OID 16546)
-- Name: orders orders_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(branch_id);


--
-- TOC entry 3875 (class 2606 OID 16627)
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- TOC entry 3879 (class 2606 OID 16653)
-- Name: payments payments_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE CASCADE;


--
-- TOC entry 3876 (class 2606 OID 16566)
-- Name: stock_history stock_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_history
    ADD CONSTRAINT stock_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(user_id);


--
-- TOC entry 3877 (class 2606 OID 16561)
-- Name: stock_history stock_history_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_history
    ADD CONSTRAINT stock_history_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id);


--
-- TOC entry 3885 (class 2606 OID 16720)
-- Name: stock_mutations stock_mutations_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_mutations
    ADD CONSTRAINT stock_mutations_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(branch_id);


--
-- TOC entry 3886 (class 2606 OID 16725)
-- Name: stock_mutations stock_mutations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_mutations
    ADD CONSTRAINT stock_mutations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- TOC entry 3887 (class 2606 OID 16715)
-- Name: stock_mutations stock_mutations_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_mutations
    ADD CONSTRAINT stock_mutations_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id);


--
-- TOC entry 3880 (class 2606 OID 16695)
-- Name: transfers transfers_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(user_id);


--
-- TOC entry 3881 (class 2606 OID 16690)
-- Name: transfers transfers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- TOC entry 3882 (class 2606 OID 16675)
-- Name: transfers transfers_from_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_from_branch_id_fkey FOREIGN KEY (from_branch_id) REFERENCES public.branches(branch_id);


--
-- TOC entry 3883 (class 2606 OID 16685)
-- Name: transfers transfers_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id);


--
-- TOC entry 3884 (class 2606 OID 16680)
-- Name: transfers transfers_to_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_to_branch_id_fkey FOREIGN KEY (to_branch_id) REFERENCES public.branches(branch_id);


--
-- TOC entry 3870 (class 2606 OID 16509)
-- Name: user_branch_roles user_branch_roles_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_branch_roles
    ADD CONSTRAINT user_branch_roles_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(branch_id);


--
-- TOC entry 3871 (class 2606 OID 16504)
-- Name: user_branch_roles user_branch_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_branch_roles
    ADD CONSTRAINT user_branch_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


-- Completed on 2026-04-21 22:17:22 WIB

--
-- PostgreSQL database dump complete
--

\unrestrict AL7lUIHxMCsELD4MN8harvWr0GCp5JHlOOXDb6dxgSgNXJVDeuPYjw3eMNvExke

