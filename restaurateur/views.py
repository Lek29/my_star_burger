from django import forms
from django.conf import settings
from django.contrib.auth import authenticate, login
from django.contrib.auth import views as auth_views
from django.contrib.auth.decorators import user_passes_test
from django.shortcuts import redirect, render
from django.urls import reverse_lazy
from django.views import View
from geopy.distance import great_circle

from foodcartapp.models import Order, Product, Restaurant
from geocoordinates.utils import fetch_coordinates


class Login(forms.Form):
    username = forms.CharField(
        label='Логин', max_length=75, required=True,
        widget=forms.TextInput(attrs={
            'class': 'form-control',
            'placeholder': 'Укажите имя пользователя'
        })
    )
    password = forms.CharField(
        label='Пароль', max_length=75, required=True,
        widget=forms.PasswordInput(attrs={
            'class': 'form-control',
            'placeholder': 'Введите пароль'
        })
    )


class LoginView(View):
    def get(self, request, *args, **kwargs):
        form = Login()
        return render(request, 'login.html', context={
            'form': form
        })

    def post(self, request):
        form = Login(request.POST)

        if form.is_valid():
            username = form.cleaned_data['username']
            password = form.cleaned_data['password']

            user = authenticate(request, username=username, password=password)
            if user:
                login(request, user)
                if user.is_staff:  # FIXME replace with specific permission
                    return redirect('restaurateur:RestaurantView')
                return redirect('start_page')

        return render(request, 'login.html', context={
            'form': form,
            'ivalid': True,
        })


class LogoutView(auth_views.LogoutView):
    next_page = reverse_lazy('restaurateur:login')


def is_manager(user):
    return user.is_staff  # FIXME replace with specific permission


@user_passes_test(is_manager, login_url='restaurateur:login')
def view_products(request):
    restaurants = list(Restaurant.objects.order_by('name'))
    products = list(Product.objects.prefetch_related('menu_items'))

    products_with_restaurant_availability = []
    for product in products:
        availability = {item.restaurant_id: item.availability for item in product.menu_items.all()}
        ordered_availability = [availability.get(restaurant.id, False) for restaurant in restaurants]

        products_with_restaurant_availability.append(
            (product, ordered_availability)
        )

    return render(request, template_name='products_list.html', context={
        'products_with_restaurant_availability': products_with_restaurant_availability,
        'restaurants': restaurants,
    })


@user_passes_test(is_manager, login_url='restaurateur:login')
def view_restaurants(request):
    return render(request, template_name='restaurants_list.html', context={
        'restaurants': Restaurant.objects.all(),
    })


@user_passes_test(is_manager, login_url='restaurateur:login')
def view_orders(request):
    orders = Order.objects.annotate_with_total_cost().prefetch_available_restaurants().filter(
        status__in=[Order.STATUS_NEW, Order.STATUS_PREPARING]
    ).order_by('created_at')

    order_records = []
    for order in orders:

        assigned_restaurant_distance = None
        if order.restaurant and order.delivery_address:

            order_coords = fetch_coordinates(settings.YANDEX_GEOCODER_API_KEY, order.delivery_address)
            restaurant_coords = fetch_coordinates(settings.YANDEX_GEOCODER_API_KEY, order.restaurant.address)

            if order_coords and restaurant_coords:
                order_lat, order_lon = float(order_coords[1]), float(order_coords[0])
                restaurant_lon, restaurant_lat = float(restaurant_coords[0]), float(restaurant_coords[1])
                distance = great_circle(
                    (order_lat, order_lon),
                    (restaurant_lat, restaurant_lon)
                ).km
                assigned_restaurant_distance = round(distance)

        order.assigned_restaurant_distance = assigned_restaurant_distance

        order.suitable_restaurants = []
        if order.status == Order.STATUS_NEW and not order.restaurant:

            suitable_restaurants = Order.objects.get_matching_restaurants_for_order(order)

            order.suitable_restaurants = suitable_restaurants

        order_records.append(order)

    context = {
        'order_records': order_records,
    }
    return render(request, template_name='order_items.html', context=context)
