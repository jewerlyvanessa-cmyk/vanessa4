--
-- PostgreSQL database dump
--

\restrict daoSb1gdTISrrSJCuoLNthTE3rxUbNFyGdg0plRz5bUEpAE3k8rDThdTQTzyLSY

-- Dumped from database version 16.11 (Homebrew)
-- Dumped by pg_dump version 16.11 (Homebrew)

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
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
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
-- Name: branches_branch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.branches_branch_id_seq OWNED BY public.branches.branch_id;


--
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
-- Name: customers_customer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.customers_customer_id_seq OWNED BY public.customers.customer_id;


--
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
-- Name: TABLE item_conditions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.item_conditions IS 'Stores detailed condition information for items in buyback orders';


--
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
-- Name: item_conditions_condition_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.item_conditions_condition_id_seq OWNED BY public.item_conditions.condition_id;


--
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
    quantity integer DEFAULT 1 NOT NULL,
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
-- Name: items_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.items_item_id_seq OWNED BY public.items.item_id;


--
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
-- Name: order_items_order_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.order_items_order_item_id_seq OWNED BY public.order_items.order_item_id;


--
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
-- Name: orders_order_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.orders_order_id_seq OWNED BY public.orders.order_id;


--
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
-- Name: payments_payment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.payments_payment_id_seq OWNED BY public.payments.payment_id;


--
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
-- Name: stock_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stock_history_history_id_seq OWNED BY public.stock_history.history_id;


--
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
-- Name: stock_mutations_mutation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stock_mutations_mutation_id_seq OWNED BY public.stock_mutations.mutation_id;


--
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
    source_type text DEFAULT 'stok'::text NOT NULL,
    courier text,
    CONSTRAINT transfers_source_type_check CHECK ((source_type = ANY (ARRAY['stok'::text, 'buyback'::text]))),
    CONSTRAINT transfers_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'completed'::text, 'rejected'::text])))
);


ALTER TABLE public.transfers OWNER TO postgres;

--
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
-- Name: transfers_transfer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.transfers_transfer_id_seq OWNED BY public.transfers.transfer_id;


--
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
-- Name: uploaded_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.uploaded_files_id_seq OWNED BY public.uploaded_files.id;


--
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
-- Name: user_branch_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_branch_roles_id_seq OWNED BY public.user_branch_roles.id;


--
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
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_user_id_seq OWNED BY public.users.user_id;


--
-- Name: branches branch_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.branches ALTER COLUMN branch_id SET DEFAULT nextval('public.branches_branch_id_seq'::regclass);


--
-- Name: customers customer_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers ALTER COLUMN customer_id SET DEFAULT nextval('public.customers_customer_id_seq'::regclass);


--
-- Name: item_conditions condition_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_conditions ALTER COLUMN condition_id SET DEFAULT nextval('public.item_conditions_condition_id_seq'::regclass);


--
-- Name: items item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items ALTER COLUMN item_id SET DEFAULT nextval('public.items_item_id_seq'::regclass);


--
-- Name: order_items order_item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items ALTER COLUMN order_item_id SET DEFAULT nextval('public.order_items_order_item_id_seq'::regclass);


--
-- Name: orders order_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders ALTER COLUMN order_id SET DEFAULT nextval('public.orders_order_id_seq'::regclass);


--
-- Name: payments payment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments ALTER COLUMN payment_id SET DEFAULT nextval('public.payments_payment_id_seq'::regclass);


--
-- Name: stock_history history_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_history ALTER COLUMN history_id SET DEFAULT nextval('public.stock_history_history_id_seq'::regclass);


--
-- Name: stock_mutations mutation_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_mutations ALTER COLUMN mutation_id SET DEFAULT nextval('public.stock_mutations_mutation_id_seq'::regclass);


--
-- Name: transfers transfer_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers ALTER COLUMN transfer_id SET DEFAULT nextval('public.transfers_transfer_id_seq'::regclass);


--
-- Name: uploaded_files id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uploaded_files ALTER COLUMN id SET DEFAULT nextval('public.uploaded_files_id_seq'::regclass);


--
-- Name: user_branch_roles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_branch_roles ALTER COLUMN id SET DEFAULT nextval('public.user_branch_roles_id_seq'::regclass);


--
-- Name: users user_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN user_id SET DEFAULT nextval('public.users_user_id_seq'::regclass);


--
-- Data for Name: branches; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.branches (branch_id, name, code, alias, initials, address, phone_number, created_at, updated_at, status) FROM stdin;
1	Toko Emas Vanessa Brangkal	303	Emas Brangkal	BGE	Pasar Brangkal	09888888	2025-12-26 22:39:47.854303	2025-12-26 22:39:47.854303	active
2	Toko Emas Vanessa Pohjejer	301	Emas Pohjejer	PJE	Pasar Pohjejer	\N	2025-12-27 22:29:45.78485	2026-04-14 22:37:01.084316	active
3	Workshop Vanessa Kendalsari	201	Bengkel Kendalsari	WKS	Kendalsari	088888888888	2025-12-28 13:31:29.581898	2025-12-28 13:31:29.581898	active
4	Cabang Utama	101	Main Branch	PUS	Jl. Raya No. 123	\N	2026-01-04 15:13:25.314928	2026-01-04 15:13:25.314928	active
5	Toko Emas Vanessa Dinoyo	302	Emas Dinoyo	DNE	Pasar Dinoyo	\N	2026-04-28 09:10:28.691971	2026-04-28 09:10:28.691971	active
6	Toko Vanessa Collection Kendalsari	501	Kendalsari Collection	KSC	\N	\N	2026-04-28 09:10:28.691971	2026-04-28 09:10:28.691971	active
7	Toko Silver Vanessa Pohjejer	401	Silver Pojejer	PJS	\N	\N	2026-04-28 09:10:28.691971	2026-04-28 09:10:28.691971	active
8	Toko Silver Pohjejer Terminal	402	Silver Pohjejer Terminal	PST	\N	\N	2026-04-28 09:10:28.691971	2026-04-28 09:10:28.691971	active
\.


--
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customers (customer_id, name, phone, address, metadata, created_at, updated_at, branch_id) FROM stdin;
20	Jaka	099999	Sooko	\N	2026-04-28 14:59:56.350438	2026-04-28 14:59:56.350438	\N
21	wawan	09999	surodinawan	\N	2026-04-28 15:18:35.506572	2026-04-28 15:18:35.506572	\N
22	Iqbal	08919191919	Modongan	\N	2026-04-28 15:49:32.785602	2026-04-28 15:49:32.785602	\N
\.


--
-- Data for Name: item_conditions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.item_conditions (condition_id, item_id, order_id, kondisi_fisik, kerusakan, berat_awal, berat_akhir, penyesuaian_berat, keaslian, sertifikat, nilai_resale, harga_beli, catatan_kondisi, foto_kondisi, dinilai_oleh, tanggal_penilaian, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.items (item_id, name, weight, material, purity, status, branch_id, metadata, created_at, updated_at, kategori, jenis, tipe, kode_produk, qr_code, quantity, ownership, stock_type, is_quick_registered, is_estimated, source, photo_url) FROM stdin;
75	Kalung Polos	2.1	Emas	22	sold	1	\N	2026-04-28 15:03:15.500717	2026-04-28 15:03:15.500717	PERHIASAN	KALUNG	GRESS	K0002	\N	1	pelanggan	non_inventory	f	f	manual	\N
77	Cincin Kawin	2.2	EMAS	18	sold	1	\N	2026-04-28 15:11:40.764572	2026-04-28 15:11:40.764572	PERHIASAN	CINCIN	BIASA	C0003	\N	1	pelanggan	non_inventory	f	f	manual	\N
78	gelang krommpyong	1.9	EMAS	17	sold	1	\N	2026-04-28 15:19:36.464911	2026-04-28 15:19:36.464911	PERHIASAN	GELANG	BIASA	g0002	\N	1	pelanggan	non_inventory	f	f	manual	\N
79	Kalung Mata Merah	3.4	EMAS	12	sold	1	\N	2026-04-28 15:44:39.0232	2026-04-28 15:44:39.0232	PERHIASAN	KALUNG	BIASA	K0004	\N	1	pelanggan	non_inventory	f	f	manual	\N
80	Kalung Edan	4.1	EMAS	18	sold	1	\N	2026-04-28 15:50:29.141149	2026-04-28 15:50:29.141149	PERHIASAN	KALUNG	BIASA	K0009	\N	1	pelanggan	non_inventory	f	f	manual	\N
\.


--
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_items (order_item_id, order_id, item_id, nama_item, kode_produk, weight, qty, harga_per_gram, material, purity, kategori, jenis, tipe, subtotal, total, diskon, kondisi_barang, created_at, updated_at, photo_produk) FROM stdin;
32	195	75	Kalung Polos	K0002	2.10	1	987500.00	Emas	22	PERHIASAN	KALUNG	GRESS	2073750.00	2075000.00	0.00	\N	2026-04-28 15:03:15.500717	2026-04-28 15:03:15.500717	\N
33	197	77	Cincin Kawin	C0003	2.20	1	987600.00	EMAS	18	PERHIASAN	CINCIN	BIASA	2172720.00	2175000.00	0.00	\N	2026-04-28 15:11:40.764572	2026-04-28 15:11:40.764572	\N
34	198	78	gelang krommpyong	g0002	1.90	1	987700.00	EMAS	17	PERHIASAN	GELANG	BIASA	1876630.00	1880000.00	0.00	\N	2026-04-28 15:19:36.464911	2026-04-28 15:19:36.464911	\N
35	199	79	Kalung Mata Merah	K0004	3.40	1	988700.00	EMAS	12	PERHIASAN	KALUNG	BIASA	3361580.00	3365000.00	0.00	\N	2026-04-28 15:44:39.0232	2026-04-28 15:44:39.0232	\N
36	200	80	Kalung Edan	K0009	4.10	1	989500.00	EMAS	18	PERHIASAN	KALUNG	BIASA	4056950.00	4060000.00	0.00	\N	2026-04-28 15:50:29.141149	2026-04-28 15:50:29.141149	\N
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (order_id, order_type, branch_id, created_at, updated_at, diskon, total, mode, customer_id, user_id, order_number, status, jumlah) FROM stdin;
195	jual	1	2026-04-28 15:03:15.500717	2026-04-28 15:03:15.500717	0.00	2073750.00	TOKO	20	1	BGEJ63181046	pending	0.00
197	jual	1	2026-04-28 15:11:40.764572	2026-04-28 15:11:40.764572	0.00	2172720.00	TOKO	20	1	BGEJ63842892	pending	0.00
198	jual	1	2026-04-28 15:19:36.464911	2026-04-28 15:19:36.464911	0.00	1876630.00	TOKO	21	1	BGEJ64295001	pending	0.00
199	jual	1	2026-04-28 15:44:39.0232	2026-04-28 15:44:39.0232	1.00	3331350.00	TOKO	20	1	BGEJ65816932	pending	0.00
200	jual	1	2026-04-28 15:50:29.141149	2026-04-28 15:50:29.141149	0.00	4060000.00	TOKO	22	1	BGEJ66148858	pending	0.00
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payments (payment_id, order_id, amount, method, status, payment_date, notes, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: stock_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stock_history (history_id, item_id, old_status, new_status, changed_by, notes, created_at) FROM stdin;
59	75	unknown	sold	1	Order jual created	2026-04-28 15:03:15.500717
60	77	unknown	sold	1	Order jual created	2026-04-28 15:11:40.764572
61	78	unknown	sold	1	Order jual created	2026-04-28 15:19:36.464911
62	79	unknown	sold	1	Order jual created	2026-04-28 15:44:39.0232
63	80	unknown	sold	1	Order jual created	2026-04-28 15:50:29.141149
\.


--
-- Data for Name: stock_mutations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stock_mutations (mutation_id, item_id, branch_id, type, quantity, previous_stock, current_stock, notes, reference_id, reference_type, created_by, created_at) FROM stdin;
\.


--
-- Data for Name: transfers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.transfers (transfer_id, from_branch_id, to_branch_id, item_name, quantity, notes, order_id, status, created_by, approved_by, created_at, updated_at, source_type, courier) FROM stdin;
\.


--
-- Data for Name: uploaded_files; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.uploaded_files (id, filename, url, uploaded_at) FROM stdin;
\.


--
-- Data for Name: user_branch_roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_branch_roles (id, user_id, branch_id, role, is_primary) FROM stdin;
1	1	4	superadmin	f
2	1	4	Manajer	f
3	1	4	Stockist	f
31	1	1	cs	f
32	1	1	admin_toko	f
33	1	1	kasir	f
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (user_id, username, password_hash, status, created_at, updated_at) FROM stdin;
1	super	$2y$10$2RAm0oRILUzAdf2ugILzWuEvQNSIJoSfhcx.7I0z1a7aT5iPMpRCe	active	2026-04-24 21:43:16.98828	2026-04-24 21:43:16.98828
\.


--
-- Name: branches_branch_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.branches_branch_id_seq', 19, true);


--
-- Name: customers_customer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_customer_id_seq', 22, true);


--
-- Name: item_conditions_condition_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.item_conditions_condition_id_seq', 1, false);


--
-- Name: items_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.items_item_id_seq', 80, true);


--
-- Name: order_items_order_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_items_order_item_id_seq', 36, true);


--
-- Name: order_nota_seq; Type: SEQUENCE SET; Schema: public; Owner: macbookpro2019
--

SELECT pg_catalog.setval('public.order_nota_seq', 14, true);


--
-- Name: orders_order_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_order_id_seq', 200, true);


--
-- Name: payments_payment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.payments_payment_id_seq', 26, true);


--
-- Name: stock_history_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stock_history_history_id_seq', 63, true);


--
-- Name: stock_mutations_mutation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stock_mutations_mutation_id_seq', 26, true);


--
-- Name: transfers_transfer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.transfers_transfer_id_seq', 18, true);


--
-- Name: uploaded_files_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.uploaded_files_id_seq', 152, true);


--
-- Name: user_branch_roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_branch_roles_id_seq', 33, true);


--
-- Name: users_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_user_id_seq', 26, true);


--
-- Name: branches branches_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_code_key UNIQUE (code);


--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (branch_id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);


--
-- Name: item_conditions item_conditions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_conditions
    ADD CONSTRAINT item_conditions_pkey PRIMARY KEY (condition_id);


--
-- Name: items items_branch_id_kode_produk_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_branch_id_kode_produk_key UNIQUE (branch_id, kode_produk);


--
-- Name: items items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (item_id);


--
-- Name: items items_qr_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_qr_code_key UNIQUE (qr_code);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (order_item_id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (order_id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (payment_id);


--
-- Name: stock_history stock_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_history
    ADD CONSTRAINT stock_history_pkey PRIMARY KEY (history_id);


--
-- Name: stock_mutations stock_mutations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_mutations
    ADD CONSTRAINT stock_mutations_pkey PRIMARY KEY (mutation_id);


--
-- Name: transfers transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_pkey PRIMARY KEY (transfer_id);


--
-- Name: uploaded_files uploaded_files_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uploaded_files
    ADD CONSTRAINT uploaded_files_pkey PRIMARY KEY (id);


--
-- Name: user_branch_roles user_branch_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_branch_roles
    ADD CONSTRAINT user_branch_roles_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: idx_branches_initials; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_branches_initials ON public.branches USING btree (initials);


--
-- Name: idx_branches_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_branches_name ON public.branches USING btree (name);


--
-- Name: idx_customers_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_name ON public.customers USING btree (name);


--
-- Name: idx_customers_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_phone ON public.customers USING btree (phone);


--
-- Name: idx_item_conditions_dinilai_oleh; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_item_conditions_dinilai_oleh ON public.item_conditions USING btree (dinilai_oleh);


--
-- Name: idx_item_conditions_item_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_item_conditions_item_id ON public.item_conditions USING btree (item_id);


--
-- Name: idx_item_conditions_kondisi_fisik; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_item_conditions_kondisi_fisik ON public.item_conditions USING btree (kondisi_fisik);


--
-- Name: idx_item_conditions_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_item_conditions_order_id ON public.item_conditions USING btree (order_id);


--
-- Name: idx_items_branch_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_branch_id ON public.items USING btree (branch_id);


--
-- Name: idx_items_kategori; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_kategori ON public.items USING btree (kategori);


--
-- Name: idx_items_ownership; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_ownership ON public.items USING btree (ownership);


--
-- Name: idx_items_qr_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_qr_code ON public.items USING btree (qr_code);


--
-- Name: idx_items_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_status ON public.items USING btree (status);


--
-- Name: idx_items_stock_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_items_stock_type ON public.items USING btree (stock_type);


--
-- Name: idx_order_items_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_order_id ON public.order_items USING btree (order_id);


--
-- Name: idx_orders_branch_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_branch_id ON public.orders USING btree (branch_id);


--
-- Name: idx_orders_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_customer_id ON public.orders USING btree (customer_id);


--
-- Name: idx_orders_order_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_order_number ON public.orders USING btree (order_number);


--
-- Name: idx_orders_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_status ON public.orders USING btree (status);


--
-- Name: idx_orders_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_user_id ON public.orders USING btree (user_id);


--
-- Name: idx_payments_method; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_method ON public.payments USING btree (method);


--
-- Name: idx_payments_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_order_id ON public.payments USING btree (order_id);


--
-- Name: idx_payments_payment_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_payment_date ON public.payments USING btree (payment_date);


--
-- Name: idx_payments_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_status ON public.payments USING btree (status);


--
-- Name: idx_stock_mutations_branch_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_stock_mutations_branch_id ON public.stock_mutations USING btree (branch_id);


--
-- Name: idx_stock_mutations_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_stock_mutations_created_at ON public.stock_mutations USING btree (created_at);


--
-- Name: idx_stock_mutations_item_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_stock_mutations_item_id ON public.stock_mutations USING btree (item_id);


--
-- Name: idx_stock_mutations_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_stock_mutations_type ON public.stock_mutations USING btree (type);


--
-- Name: idx_transfers_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_created_at ON public.transfers USING btree (created_at);


--
-- Name: idx_transfers_from_branch; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_from_branch ON public.transfers USING btree (from_branch_id);


--
-- Name: idx_transfers_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_status ON public.transfers USING btree (status);


--
-- Name: idx_transfers_to_branch; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_to_branch ON public.transfers USING btree (to_branch_id);


--
-- Name: idx_user_branch_roles_branch_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_branch_roles_branch_id ON public.user_branch_roles USING btree (branch_id);


--
-- Name: idx_user_branch_roles_role; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_branch_roles_role ON public.user_branch_roles USING btree (role);


--
-- Name: idx_user_branch_roles_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_branch_roles_user_id ON public.user_branch_roles USING btree (user_id);


--
-- Name: idx_users_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_status ON public.users USING btree (status);


--
-- Name: item_conditions trigger_update_item_conditions_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_item_conditions_updated_at BEFORE UPDATE ON public.item_conditions FOR EACH ROW EXECUTE FUNCTION public.update_item_conditions_updated_at();


--
-- Name: customers customers_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(branch_id);


--
-- Name: orders fk_orders_customers; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_orders_customers FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id);


--
-- Name: item_conditions item_conditions_dinilai_oleh_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_conditions
    ADD CONSTRAINT item_conditions_dinilai_oleh_fkey FOREIGN KEY (dinilai_oleh) REFERENCES public.users(user_id);


--
-- Name: item_conditions item_conditions_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_conditions
    ADD CONSTRAINT item_conditions_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id) ON DELETE CASCADE;


--
-- Name: item_conditions item_conditions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_conditions
    ADD CONSTRAINT item_conditions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE CASCADE;


--
-- Name: items items_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(branch_id);


--
-- Name: order_items order_items_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id);


--
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE CASCADE;


--
-- Name: orders orders_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(branch_id);


--
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: payments payments_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE CASCADE;


--
-- Name: stock_history stock_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_history
    ADD CONSTRAINT stock_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(user_id);


--
-- Name: stock_history stock_history_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_history
    ADD CONSTRAINT stock_history_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id);


--
-- Name: stock_mutations stock_mutations_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_mutations
    ADD CONSTRAINT stock_mutations_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(branch_id);


--
-- Name: stock_mutations stock_mutations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_mutations
    ADD CONSTRAINT stock_mutations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: stock_mutations stock_mutations_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_mutations
    ADD CONSTRAINT stock_mutations_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id);


--
-- Name: transfers transfers_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(user_id);


--
-- Name: transfers transfers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);


--
-- Name: transfers transfers_from_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_from_branch_id_fkey FOREIGN KEY (from_branch_id) REFERENCES public.branches(branch_id);


--
-- Name: transfers transfers_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id);


--
-- Name: transfers transfers_to_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_to_branch_id_fkey FOREIGN KEY (to_branch_id) REFERENCES public.branches(branch_id);


--
-- Name: user_branch_roles user_branch_roles_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_branch_roles
    ADD CONSTRAINT user_branch_roles_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(branch_id);


--
-- Name: user_branch_roles user_branch_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_branch_roles
    ADD CONSTRAINT user_branch_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- PostgreSQL database dump complete
--

\unrestrict daoSb1gdTISrrSJCuoLNthTE3rxUbNFyGdg0plRz5bUEpAE3k8rDThdTQTzyLSY

