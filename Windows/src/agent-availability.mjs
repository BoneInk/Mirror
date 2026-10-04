// Service reachability is not evidence that a desktop agent is uninstalled.
export function isMissing(profile, discoveries) {
  return (
    discoveries.find((row) => row.id === profile.id)?.availability === "missing"
  );
}

export function selectableProfiles(profiles, discoveries) {
  return profiles.filter((profile) => !isMissing(profile, discoveries));
}

export function defaultProfile(profiles, discoveries, selectedID) {
  const available = selectableProfiles(profiles, discoveries);
  return (
    available.find((profile) => profile.id === selectedID) ||
    available.find((profile) =>
      discoveries.some(
        (row) => row.id === profile.id && row.availability === "available",
      ),
    )
  );
}
