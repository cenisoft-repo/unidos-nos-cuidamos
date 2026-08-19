"use client";

import { useState } from "react";
import Link from "next/link";
import { CheckCircle2, LoaderCircle, MailCheck, MapPin } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { toOperationalMessage } from "@/lib/user-errors";
import { EVENT_ID } from "@/lib/constants";

// Un solo formulario para empresa, organización, ONG, fundación, entidad y persona aportante.
// El tipo describe al aliado; el rol operativo es el mismo para todos.
export const ALLY_KINDS = [
  { value: "empresa", label: "Empresa" },
  { value: "organizacion", label: "Organización" },
  { value: "ong", label: "ONG" },
  { value: "fundacion", label: "Fundación" },
  { value: "entidad_publica", label: "Entidad" },
  { value: "persona", label: "Persona aportante" },
] as const;

type Registered = { platform_identifier: string; email: string };

export function AllyRegistrationForm() {
  // La coordenada aproximada es opcional: sirve para recomendar el punto más cercano y nunca
  // se publica como dirección exacta.
  const [coordinates, setCoordinates] = useState<{ latitude: number; longitude: number } | null>(null);
  const [locationNotice, setLocationNotice] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [registered, setRegistered] = useState<Registered | null>(null);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError("");
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") ?? "").trim().toLowerCase();
    const password = String(form.get("password") ?? "");
    const supabase = createClient();

    // El registro se valida antes de crear la identidad en Auth: así un NIT o un teléfono
    // inválido no deja una cuenta sin aliado detrás.
    const { data, error: registerError } = await supabase.rpc("register_ally", {
      p_event_id: EVENT_ID,
      p_ally_kind: String(form.get("ally_kind")),
      p_legal_name: String(form.get("legal_name") ?? "").trim(),
      p_tax_id: String(form.get("tax_id") ?? "").trim(),
      p_responsible_name: String(form.get("responsible_name") ?? "").trim(),
      p_contact_phone: String(form.get("contact_phone") ?? "").trim(),
      p_contact_email: email,
      p_public_location_text: String(form.get("public_location") ?? "").trim(),
      p_public_latitude: coordinates?.latitude ?? null,
      p_public_longitude: coordinates?.longitude ?? null,
      p_bot_field: String(form.get("website") ?? ""),
    });
    if (registerError) {
      setPending(false);
      setError(toOperationalMessage(registerError));
      return;
    }

    const { error: signUpError } = await supabase.auth.signUp({
      email,
      password,
      options: { emailRedirectTo: `${window.location.origin}/registro/confirmado` },
    });
    setPending(false);
    if (signUpError) {
      setError(toOperationalMessage(signUpError));
      return;
    }
    const row = (Array.isArray(data) ? data[0] : data) as { platform_identifier: string };
    setRegistered({ platform_identifier: row.platform_identifier, email });
  }

  if (registered) {
    return (
      <div className="form-card">
        <div className="form-body">
          <MailCheck size={38} color="var(--forest-2)" />
          <h2 style={{ marginTop: 18 }}>Confirma tu correo para activar la cuenta.</h2>
          <p className="lead" style={{ fontSize: 16 }}>
            Enviamos un mensaje a <strong>{registered.email}</strong>. La cuenta no puede registrar
            aportes hasta que abras el enlace de confirmación.
          </p>
          <div className="form-success">
            Identificador de aliado reservado: <strong>{registered.platform_identifier}</strong>
            <br />
            Es tu identidad dentro de la plataforma, no un buzón de correo.
          </div>
          <p className="form-notice">
            <CheckCircle2 size={16} /> Después de confirmar, vuelve a <Link href="/registro/confirmado">activar tu cuenta ALIADO</Link>.
          </p>
        </div>
      </div>
    );
  }

  return (
    <form className="form-card" onSubmit={handleSubmit}>
      <div className="form-card-header">
        <h2>Regístrate como aliado</h2>
        <p>Un solo registro para empresas, organizaciones, ONG, fundaciones, entidades y personas aportantes.</p>
      </div>
      <div className="form-body">
        {error && <p className="form-error" role="alert">{error}</p>}
        <div className="form-honeypot" aria-hidden="true">
          <label htmlFor="website">Sitio web</label>
          <input id="website" name="website" tabIndex={-1} autoComplete="off" />
        </div>
        <div className="field">
          <label htmlFor="ally_kind">¿Quién aporta?</label>
          <select id="ally_kind" name="ally_kind" required defaultValue="">
            <option value="" disabled>Selecciona</option>
            {ALLY_KINDS.map((kind) => <option key={kind.value} value={kind.value}>{kind.label}</option>)}
          </select>
          <small>Todos los perfiles operan con el mismo rol ALIADO.</small>
        </div>
        <div className="field">
          <label htmlFor="legal_name">Nombre o razón social</label>
          <input id="legal_name" name="legal_name" minLength={3} maxLength={160} required />
        </div>
        <div className="field-grid">
          <div className="field">
            <label htmlFor="tax_id">Identificación o NIT</label>
            <input id="tax_id" name="tax_id" minLength={5} maxLength={40} required />
          </div>
          <div className="field">
            <label htmlFor="contact_phone">Teléfono de contacto</label>
            <input id="contact_phone" name="contact_phone" type="tel" minLength={7} maxLength={30} required />
          </div>
        </div>
        <div className="field">
          <label htmlFor="responsible_name">Responsable</label>
          <input id="responsible_name" name="responsible_name" minLength={3} maxLength={120} required />
          <small>Persona que responde por los aportes registrados.</small>
        </div>
        <div className="field">
          <label htmlFor="public_location">Zona pública desde la que entregas</label>
          <input id="public_location" name="public_location" minLength={4} maxLength={120} required placeholder="Municipio y sector amplio" />
          <small>Se usa para crear tu punto de acopio. No escribas la dirección exacta.</small>
          <div className="center-proximity">
            <button className="button button-outline button-small" type="button" onClick={() => {
              if (!navigator.geolocation) {
                setLocationNotice("Este navegador no puede compartir tu ubicación.");
                return;
              }
              navigator.geolocation.getCurrentPosition(
                (position) => {
                  setCoordinates({ latitude: position.coords.latitude, longitude: position.coords.longitude });
                  setLocationNotice("Coordenada aproximada registrada.");
                },
                () => setLocationNotice("No compartiste tu ubicación; el registro sigue siendo válido."),
                { enableHighAccuracy: false, timeout: 8000, maximumAge: 300000 },
              );
            }}><MapPin size={14} /> Usar mi ubicación aproximada</button>
            {locationNotice && <small role="status">{locationNotice}</small>}
          </div>
        </div>
        <div className="field">
          <label htmlFor="email">Correo de contacto</label>
          <input id="email" name="email" type="email" autoComplete="email" maxLength={160} required />
          <small>A este correo llega la confirmación que activa la cuenta.</small>
        </div>
        <div className="field">
          <label htmlFor="password">Contraseña</label>
          <input id="password" name="password" type="password" autoComplete="new-password" minLength={12} required />
          <small>Mínimo 12 caracteres con mayúsculas, minúsculas, dígitos y un símbolo.</small>
        </div>
        <label className="form-check">
          <input type="checkbox" required />
          <span>Confirmo que los datos del aliado son verídicos y que puedo responder por ellos.</span>
        </label>
        <button className="button button-dark button-block" disabled={pending} type="submit">
          {pending ? <><LoaderCircle size={17} /> Registrando…</> : "Crear cuenta de aliado"}
        </button>
        <p className="form-notice">¿Ya tienes cuenta? <Link href="/ingresar">Ingresa aquí</Link>.</p>
      </div>
    </form>
  );
}
