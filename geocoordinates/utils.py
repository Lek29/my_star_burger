import requests
from django.utils import timezone

from geocoordinates.models import GeocodedAddress


def fetch_coordinates(apikey, address):
    if not address:
        return None

    geocoded_obj, created = GeocodedAddress.objects.get_or_create(address=address)

    if not created and geocoded_obj.latitude is not None and geocoded_obj.longitude is not None:
        return geocoded_obj.longitude, geocoded_obj.latitude

    base_url = 'https://geocode-maps.yandex.ru/1.x'
    params = {
        'apikey': apikey,
        'geocode': address,
        'format': 'json',
    }
    try:
        response = requests.get(base_url, params=params)
        response.raise_for_status()
        places_found = response.json().get('response', {}).get('GeoObjectCollection', {}).get('featureMember', [])

        if not places_found:
            geocoded_obj.latitude = None
            geocoded_obj.longitude = None

        else:
            most_relevant = places_found[0]
            lon, lat = most_relevant['GeoObject']['Point']['pos'].split(' ')
            geocoded_obj.latitude = float(lat)
            geocoded_obj.longitude = float(lon)

        geocoded_obj.queried_at = timezone.now()
        geocoded_obj.save()

        if geocoded_obj.latitude is not None and geocoded_obj.longitude is not None:
            return geocoded_obj.longitude, geocoded_obj.latitude
        else:
            return None

    except requests.exceptions.RequestException as e:
        return None
    except Exception as e:
        return None
