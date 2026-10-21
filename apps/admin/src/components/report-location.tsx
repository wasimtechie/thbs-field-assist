import {MapPin,ArrowUpRight} from 'lucide-react';
import type {ReportLocation} from '@field-assist/contracts';
import {formatTime} from '@/lib/api';
import styles from './report-location.module.css';

export function LocationSummary({location}:{location?:ReportLocation|null}){
 if(!location)return <span className="muted">Not captured</span>;
 return <span className={styles.summary} title={`Captured ${formatTime(location.capturedAt)} · Accuracy ±${Math.round(location.accuracyMeters)} m${location.isMocked?' · Simulated location':''}`}><MapPin size={14}/><span>{location.latitude.toFixed(5)}, {location.longitude.toFixed(5)}<small>±{Math.round(location.accuracyMeters)} m{location.isMocked?' · Simulated':''}</small></span></span>;
}

export function ReportLocationCard({location}:{location?:ReportLocation|null}){
 return <section className={`panel ${styles.card}`} aria-label="Report location"><div className="panel-heading"><div><h2>Report location</h2><p>Captured on the device at confirmation</p></div><MapPin size={20}/></div>{location?<div className={styles.body}><LocationSummary location={location}/>{location.isMocked&&<p className={styles.note}>Simulated location reported by the device.</p>}<dl><dt>Accuracy</dt><dd>±{Math.round(location.accuracyMeters)} metres</dd><dt>Captured on device</dt><dd>{new Date(location.capturedAt).toLocaleString('en-GB',{timeZone:'UTC'})} UTC</dd></dl><a className="button secondary" href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${location.latitude},${location.longitude}`)}`} target="_blank" rel="noopener noreferrer">Open map <ArrowUpRight size={15}/></a><p className={styles.note}>This is the report’s captured position. Upload time is recorded separately in the receipt.</p></div>:<p className={styles.body}>Location was not captured for this report. Reports submitted with the updated app include it.</p>}</section>;
}
