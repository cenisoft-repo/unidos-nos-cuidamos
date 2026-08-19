"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { BadgeCheck, LoaderCircle, LockKeyhole, MailCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { toOperationalMessage } from "@/lib/user-errors";

type Activation = { organization_name: string; platform_identifier: string };
type Phase = "checking" | "anonymous" | "unconfirmed" | "activated" | "failed";

// El enlace del correo devuelve a esta pantalla. El cliente del navegador resuelve la sesión a
// partir de la URL, así que damos algunos intentos antes de concluir que nadie inició sesión.
const SESSION_ATTEMPTS = 6;
const SESSION_RETRY_MS = 400;

export function AllyActivationPanel() {
  const [phase, setPhase] = useState<Phase>("checking");
  const [activation, setActivation] = useState<Activation | null>(null);
  const [error, setError] = useState("");

  const activate = useCallback(async () => {
    const supabase = createClient();
    let user = null;
    for (let attempt = 0; attempt < SESSION_ATTEMPTS && !user; attempt += 1) {
      const { data } = await supabase.auth.getUser();
      user = data.user;
      if (!user) await new Promise((resolve) => setTimeout(resolve, SESSION_RETRY_MS));
    }
    if (!user) {
      setPhase("anonymous");
      return;
    }
    const { data, error: activationError } = await supabase.rpc("activate_ally_registration");
    if (activationError) {
      setError(toOperationalMessage(activationError));
      setPhase(user.email_confirmed_at ? "failed" : "unconfirmed");
      return;
    }
    const row = (Array.isArray(data) ? data[0] : data) as Activation | undefined;
    if (!row) {
      setError("No fue posible completar la activación. Intenta de nuevo en unos minutos.");
      setPhase("failed");
      return;
    }
    setActivation(row);
    setPhase("activated");
  }, []);

  useEffect(() => {
    // La activación se difiere un tick: el efecto no debe cambiar estado de forma síncrona.
    const started = window.setTimeout(() => void activate(), 0);
    return () => window.clearTimeout(started);
  }, [activate]);

  if (phase === "checking") {
    return <div className="form-card"><div className="form-body"><LoaderCircle size={34} color="var(--forest-2)" /><h2 style={{ marginTop: 18 }}>Activando tu cuenta…</h2><p>Estamos comprobando la confirmación del correo.</p></div></div>;
  }

  if (phase === "anonymous") {
    return (
      <div className="form-card"><div className="form-body">
        <LockKeyhole size={34} color="var(--forest-2)" />
        <h2 style={{ marginTop: 18 }}>Ingresa para activar la cuenta.</h2>
        <p>Ya confirmaste el correo o abriste el enlace en otro navegador. Inicia sesión y volvemos a este paso automáticamente.</p>
        <Link className="button button-dark" href="/ingresar?next=/registro/confirmado">Ingresar</Link>
      </div></div>
    );
  }

  if (phase === "unconfirmed") {
    return (
      <div className="form-card"><div className="form-body">
        <MailCheck size={34} color="var(--forest-2)" />
        <h2 style={{ marginTop: 18 }}>Falta confirmar el correo.</h2>
        <p>{error || "Abre el enlace que enviamos a tu correo y vuelve a esta página."}</p>
      </div></div>
    );
  }

  if (phase === "failed") {
    return (
      <div className="form-card"><div className="form-body">
        <h2>No pudimos activar la cuenta.</h2>
        <p className="form-error" role="alert">{error}</p>
        <Link className="button button-dark" href="/registro">Volver al registro</Link>
      </div></div>
    );
  }

  return (
    <div className="form-card"><div className="form-body">
      <BadgeCheck size={38} color="var(--forest-2)" />
      <h2 style={{ marginTop: 18 }}>Cuenta ALIADO activa.</h2>
      <p className="lead" style={{ fontSize: 16 }}>Ya puedes registrar aportes a nombre de <strong>{activation?.organization_name}</strong>.</p>
      <div className="form-success">
        Identificador de aliado: <strong>{activation?.platform_identifier}</strong>
        <br />Es tu identidad dentro de la plataforma, no un buzón de correo.
      </div>
      <Link className="button button-dark" href="/donar">Registrar un aporte</Link>
    </div></div>
  );
}
